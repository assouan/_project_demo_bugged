# Project Demo Bugged

Ce depot porte l'IaC applicative du journal de demonstration. La fondation du
Project et le tenant Kubernetes restent geres par la Landing Zone ; cette stack
ne cree que la workload dans le namespace `project-demo-bugged-dev`.

## Ressources

- un ConfigMap contenant le site et son serveur HTTP minimal ;
- un Deployment mono-replica, non-root, sans token Kubernetes, avec filesystem
  racine en lecture seule et ressources bornees ;
- un Service prive `ClusterIP` sur le port `8080` ;
- un default-deny applicatif et une ouverture HTTP limitee au namespace.

Le site n'ajoute aucun Load Balancer, volume ou cout cloud fixe. Toutes les
ressources applicatives sont supprimees par le plan Terraform `Destroy`.

## State Kubernetes

Le backend `kubernetes` conserve le state dans le Secret
`tfstate-default-project-demo-bugged-journal` du namespace du tenant. Terraform
utilise une Lease du meme namespace pour le verrouillage. Le ServiceAccount CI
doit donc disposer des droits limites aux Secrets et Leases de ce namespace ;
ces droits sont fournis par la fondation tenant.

Le Secret de state subsiste apres la destruction de la workload afin de pouvoir
la recreer. Il disparait avec le namespace lors de la suppression du tenant.

## Pipeline Jenkins

Le `Jenkinsfile` accepte :

- `ACTION` : `Apply` ou `Destroy` ;
- `GIT_REF` : branche, tag complet ou SHA Git ;
- `CONFIRM_DESTROY` : confirmation obligatoire pour `Destroy`.

Chaque build utilise le ServiceAccount `project-demo-bugged-dev-ci`. Son token
projete n'est monte que dans le conteneur Terraform. Le pipeline valide le
depot, initialise le backend avec le lock versionne, produit un plan binaire et
applique exactement ce plan. Un echec peut ouvrir un diagnostic dans le helper,
sans transmettre la console Jenkins ni un credential.

Le wrapper local configure le Folder, le credential HMAC et le Pipeline SCM de
maniere idempotente :

```powershell
$env:ALTEN_AI_HELPER_KEY = '<cle du POC>'
./jenkins.ps1 -Action configure
./jenkins.ps1 -Action status
./jenkins.ps1 -Action build -TerraformAction Apply -GitRef main
./jenkins.ps1 -Action build -TerraformAction Destroy -GitRef main -ConfirmDestroy
./jenkins.ps1 -Action remove -ConfirmRemoval
```

Le mot de passe Jenkins est lu en memoire via `10-cicd/deploy.ps1`; il n'est ni
affiche ni ecrit. Le wrapper exige le gateway local
`https://jenkins.alten:9001` avec un certificat approuve par Windows.

## Validation locale sans cluster

```powershell
python ./scripts/validate.py
terraform fmt -check -recursive
terraform init -backend=false -input=false -lockfile=readonly
terraform validate
```

Ces commandes ne deploient rien et ne lisent pas le state distant.
