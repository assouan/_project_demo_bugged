[CmdletBinding()]
param(
  [ValidateSet('configure', 'remove', 'build', 'status')]
  [string]$Action = 'status',

  [ValidateSet('Apply', 'Destroy')]
  [string]$TerraformAction = 'Apply',

  [string]$GitRef = 'main',

  [uri]$JenkinsUrl = 'https://jenkins.alten:9001',

  [ValidateRange(60, 3600)]
  [int]$BuildTimeoutSeconds = 900,

  [switch]$ConfirmDestroy,

  [switch]$ConfirmRemoval
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Net.Http

$repositoryDirectory = $PSScriptRoot
$landingZoneDirectory = Split-Path $repositoryDirectory -Parent
$cicdScript = Join-Path $landingZoneDirectory '10-cicd/deploy.ps1'
$folderName = 'project-demo-bugged'
$jobName = 'journal'
$credentialId = 'ai-helper-trigger-key'
$repositoryUrl = 'https://github.com/assouan/_project_demo_bugged.git'
$folderPath = "/job/$folderName"
$jobPath = "$folderPath/job/$jobName"
$baseUri = $JenkinsUrl.AbsoluteUri.TrimEnd('/')
$script:jenkinsSession = $null
$script:jenkinsHeaders = @{}

if ($JenkinsUrl.Scheme -ne 'https' -or $JenkinsUrl.Host -ne 'jenkins.alten') {
  throw 'JenkinsUrl doit cibler le gateway local HTTPS jenkins.alten.'
}
if (-not (Test-Path -LiteralPath $cicdScript -PathType Leaf)) {
  throw 'Le wrapper 10-cicd est introuvable.'
}
if (
  $GitRef.Length -lt 1 -or
  $GitRef.Length -gt 200 -or
  $GitRef.Contains('..') -or
  $GitRef.Contains('@{') -or
  $GitRef.EndsWith('/') -or
  $GitRef -notmatch '^(?:[0-9a-f]{40}|(?:refs/(?:heads|tags)/)?[A-Za-z0-9][A-Za-z0-9._/-]*)$'
) {
  throw 'GitRef est invalide.'
}

function Get-JenkinsPassword {
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = @(& $cicdScript -Action password 2>&1)
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    $null = $output
    throw 'Impossible de recuperer le credential administrateur Jenkins.'
  }
  $values = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
  $null = $output
  $candidate = $values | Select-Object -Last 1
  $null = $values
  if (
    -not $candidate -or
    $candidate.Length -lt 16 -or
    $candidate.Length -gt 256 -or
    $candidate -cnotmatch '^[!-~]+$'
  ) {
    $candidate = $null
    throw 'Le credential administrateur Jenkins est invalide.'
  }
  $candidate
}

function Initialize-JenkinsSession {
  $password = Get-JenkinsPassword
  try {
    $basicToken = [Convert]::ToBase64String(
      [Text.Encoding]::UTF8.GetBytes("admin:$password")
    )
    $script:jenkinsHeaders = @{ Authorization = "Basic $basicToken" }
    try {
      $crumb = Invoke-RestMethod -Uri "$baseUri/crumbIssuer/api/json" -Headers $script:jenkinsHeaders -SessionVariable jenkinsSession -TimeoutSec 15
    }
    catch {
      throw 'Jenkins ne repond pas avec un certificat approuve et un compte valide.'
    }
    if (-not $crumb.crumbRequestField -or -not $crumb.crumb) {
      throw 'Jenkins n a pas retourne de jeton CSRF.'
    }
    $script:jenkinsSession = $jenkinsSession
    $script:jenkinsHeaders[$crumb.crumbRequestField] = $crumb.crumb
  }
  finally {
    $password = $null
    $basicToken = $null
  }
}

function Test-JenkinsPath {
  param(
    [Parameter(Mandatory)]
    [string]$Path
  )

  $handler = [Net.Http.HttpClientHandler]::new()
  $handler.UseProxy = $false
  $client = [Net.Http.HttpClient]::new($handler)
  $client.Timeout = [TimeSpan]::FromSeconds(15)
  $request = [Net.Http.HttpRequestMessage]::new(
    [Net.Http.HttpMethod]::Get,
    "$baseUri$Path/config.xml"
  )
  $response = $null
  try {
    $authorization = "$($script:jenkinsHeaders.Authorization)" -split ' ', 2
    if ($authorization.Count -ne 2 -or $authorization[0] -cne 'Basic') {
      throw 'Le contexte authentifie Jenkins est invalide.'
    }
    $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new(
      $authorization[0],
      $authorization[1]
    )
    $response = $client.SendAsync($request).GetAwaiter().GetResult()
    if ([int]$response.StatusCode -eq 200) {
      return $true
    }
    if ([int]$response.StatusCode -eq 404) {
      return $false
    }
    throw "Statut Jenkins inattendu : $([int]$response.StatusCode)."
  }
  catch {
    throw "Impossible de verifier l objet Jenkins $Path."
  }
  finally {
    $authorization = $null
    if ($response) {
      $response.Dispose()
    }
    $request.Dispose()
    $client.Dispose()
    $handler.Dispose()
  }
}

function Set-JenkinsXml {
  param(
    [Parameter(Mandatory)]
    [string]$CreatePath,

    [Parameter(Mandatory)]
    [string]$UpdatePath,

    [Parameter(Mandatory)]
    [string]$ProbePath,

    [Parameter(Mandatory)]
    [string]$Xml
  )

  $exists = Test-JenkinsPath -Path $ProbePath
  $target = if ($exists) { $UpdatePath } else { $CreatePath }
  try {
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUri$target" -Method Post -Headers $script:jenkinsHeaders -WebSession $script:jenkinsSession -ContentType 'application/xml; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($Xml)) -TimeoutSec 30 | Out-Null
  }
  catch {
    throw "Impossible de configurer l objet Jenkins $ProbePath."
  }
}

function Get-HelperKey {
  if ($env:ALTEN_AI_HELPER_KEY) {
    $value = $env:ALTEN_AI_HELPER_KEY
  }
  else {
    $secureValue = Read-Host 'Cle du helper' -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
      $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
      $secureValue.Dispose()
    }
  }
  if ($value.Length -lt 6 -or $value.Length -gt 128) {
    $value = $null
    throw 'La cle du helper doit contenir entre 6 et 128 caracteres.'
  }
  $value
}

function Set-Folder {
  $folderXml = @'
<?xml version="1.1" encoding="UTF-8"?>
<com.cloudbees.hudson.plugins.folder.Folder plugin="cloudbees-folder">
  <actions />
  <description>Projet de demonstration - journal et remediation assistee.</description>
  <properties />
  <folderViews class="com.cloudbees.hudson.plugins.folder.views.DefaultFolderViewHolder">
    <views class="hudson.model.AllView$1" />
    <tabBar class="hudson.views.DefaultViewsTabBar" />
  </folderViews>
  <healthMetrics />
  <icon class="com.cloudbees.hudson.plugins.folder.icons.StockFolderIcon" />
</com.cloudbees.hudson.plugins.folder.Folder>
'@
  Set-JenkinsXml -CreatePath "/createItem?name=$([uri]::EscapeDataString($folderName))" -UpdatePath "$folderPath/config.xml" -ProbePath $folderPath -Xml $folderXml
}

function Set-HelperCredential {
  $helperKey = Get-HelperKey
  try {
    $escapedKey = [Security.SecurityElement]::Escape($helperKey)
    $credentialXml = @"
<?xml version="1.1" encoding="UTF-8"?>
<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl plugin="plain-credentials">
  <scope>GLOBAL</scope>
  <id>$credentialId</id>
  <description>Signature HMAC du helper de remediation.</description>
  <secret>$escapedKey</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
"@
    $credentialPath = "$folderPath/credentials/store/folder/domain/_/credential/$credentialId"
    $createPath = "$folderPath/credentials/store/folder/domain/_/createCredentials"
    Set-JenkinsXml -CreatePath $createPath -UpdatePath "$credentialPath/config.xml" -ProbePath $credentialPath -Xml $credentialXml
  }
  finally {
    $helperKey = $null
    $escapedKey = $null
    $credentialXml = $null
  }
}

function Set-PipelineJob {
  $escapedRepositoryUrl = [Security.SecurityElement]::Escape($repositoryUrl)
  $jobXml = @"
<?xml version="1.1" encoding="UTF-8"?>
<flow-definition plugin="workflow-job">
  <actions />
  <description>Deploiement parametre du journal de demonstration.</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.ChoiceParameterDefinition>
          <name>ACTION</name>
          <description>Operation Terraform.</description>
          <choices class="java.util.Arrays`$ArrayList">
            <a class="string-array">
              <string>Apply</string>
              <string>Destroy</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>GIT_REF</name>
          <description>Branche, tag complet ou SHA Git.</description>
          <defaultValue>main</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>CONFIRM_DESTROY</name>
          <description>Confirmation obligatoire pour Destroy.</description>
          <defaultValue>false</defaultValue>
        </hudson.model.BooleanParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>$escapedRepositoryUrl</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="empty-list" />
      <extensions />
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers />
  <disabled>false</disabled>
</flow-definition>
"@
  Set-JenkinsXml -CreatePath "$folderPath/createItem?name=$([uri]::EscapeDataString($jobName))" -UpdatePath "$jobPath/config.xml" -ProbePath $jobPath -Xml $jobXml
}

function Start-PipelineBuild {
  if (-not (Test-JenkinsPath -Path $jobPath)) {
    throw 'Le Pipeline Jenkins doit etre configure avant son declenchement.'
  }
  if ($TerraformAction -eq 'Destroy' -and -not $ConfirmDestroy) {
    throw 'ConfirmDestroy est obligatoire pour declencher Destroy.'
  }

  $query = [string]::Join('&', @(
      "ACTION=$([uri]::EscapeDataString($TerraformAction))",
      "GIT_REF=$([uri]::EscapeDataString($GitRef))",
      "CONFIRM_DESTROY=$($ConfirmDestroy.IsPresent.ToString().ToLowerInvariant())"
    ))
  try {
    $queueResponse = Invoke-WebRequest -UseBasicParsing -Uri "$baseUri$jobPath/buildWithParameters?$query" -Method Post -Headers $script:jenkinsHeaders -WebSession $script:jenkinsSession -TimeoutSec 30
  }
  catch {
    throw 'Impossible de placer le build Jenkins dans la file.'
  }
  $queueLocation = [string]$queueResponse.Headers.Location
  if ($queueLocation -notmatch '/queue/item/(?<id>[0-9]+)/') {
    throw 'Jenkins n a pas retourne d identifiant de file.'
  }
  $queueId = $Matches.id

  $deadline = [DateTimeOffset]::UtcNow.AddSeconds($BuildTimeoutSeconds)
  $buildNumber = $null
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $queueItem = Invoke-RestMethod -Uri "$baseUri/queue/item/$queueId/api/json" -Headers $script:jenkinsHeaders -WebSession $script:jenkinsSession -TimeoutSec 15
    if ($queueItem.cancelled) {
      throw 'Le build Jenkins a ete annule dans la file.'
    }
    if ($queueItem.executable.number) {
      $buildNumber = [int]$queueItem.executable.number
      break
    }
    Start-Sleep -Seconds 2
  }
  if ($null -eq $buildNumber) {
    throw 'Le build Jenkins n a pas demarre avant le timeout.'
  }

  $build = $null
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $build = Invoke-RestMethod -Uri "$baseUri$jobPath/$buildNumber/api/json" -Headers $script:jenkinsHeaders -WebSession $script:jenkinsSession -TimeoutSec 15
    if (-not $build.building) {
      break
    }
    Start-Sleep -Seconds 3
  }
  if ($null -eq $build -or $build.building) {
    throw 'Le build Jenkins n a pas termine avant le timeout.'
  }

  $result = [ordered]@{
    status       = 'jenkins-build-complete'
    action       = $TerraformAction
    git_ref      = $GitRef
    build_number = $buildNumber
    result       = "$($build.result)"
    url          = "$baseUri$jobPath/$buildNumber/"
  }
  $result | ConvertTo-Json -Compress
  if ($build.result -ne 'SUCCESS') {
    throw "Le build Jenkins a termine avec le statut $($build.result)."
  }
}

Initialize-JenkinsSession

switch ($Action) {
  'configure' {
    Set-Folder
    Set-HelperCredential
    Set-PipelineJob
    Write-Output '{"status":"jenkins-project-configured","folder":"project-demo-bugged","job":"journal","credential_emitted":false}'
  }
  'remove' {
    if (-not $ConfirmRemoval) {
      throw 'ConfirmRemoval est obligatoire pour supprimer le Folder Jenkins.'
    }
    if (Test-JenkinsPath -Path $folderPath) {
      try {
        Invoke-WebRequest -UseBasicParsing -Uri "$baseUri$folderPath/doDelete" -Method Post -Headers $script:jenkinsHeaders -WebSession $script:jenkinsSession -TimeoutSec 30 | Out-Null
      }
      catch {
        throw 'Impossible de supprimer le Folder Jenkins.'
      }
    }
    Write-Output '{"status":"jenkins-project-removed","folder":"project-demo-bugged"}'
  }
  'build' {
    Start-PipelineBuild
  }
  'status' {
    if (-not (Test-JenkinsPath -Path $jobPath)) {
      Write-Output '{"status":"jenkins-project-absent","folder":"project-demo-bugged","job":"journal"}'
    }
    else {
      $job = Invoke-RestMethod -Uri "$baseUri$jobPath/api/json" -Headers $script:jenkinsHeaders -WebSession $script:jenkinsSession -TimeoutSec 15
      [ordered]@{
        status = 'jenkins-project-ready'
        folder = $folderName
        job    = $jobName
        color  = "$($job.color)"
        url    = "$baseUri$jobPath/"
      } | ConvertTo-Json -Compress
    }
  }
}
