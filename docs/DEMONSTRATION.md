# Démonstration de la soutenance — plateforme GitOps sécurisée sur Amazon EKS

Durée totale : **20 à 25 minutes**. Chaque partie suit le même déroulé : on dit ce qu'on va montrer,
on lance la commande, on commente le résultat.

Toutes les commandes se lancent **depuis le poste Ubuntu** (`kubectl` déjà configuré par
`outils/acces-poste/installer.sh`). Elles sont testées sur la plateforme réelle.

| Adresse | Rôle |
|---|---|
| https://argocd.elyse-cloud.duckdns.org | ArgoCD (état GitOps du cluster) |
| https://grafana.elyse-cloud.duckdns.org | Grafana (supervision, tableau de bord Conformité) |
| https://dev.elyse-cloud.duckdns.org/api/ | API du portail, environnement dev |
| https://staging.elyse-cloud.duckdns.org/api/ | API du portail, environnement staging |
| https://prod.elyse-cloud.duckdns.org/api/ | API du portail, environnement prod |
| https://github.com/cloudarmelpro | Les trois dépôts du projet |

---

## Partie 0 — Préparation (la veille et 30 minutes avant)

### La veille

1. **Allumer l'environnement** s'il est arrêté (25 minutes, tout se réinstalle seul) :
   - depuis le poste Windows : `bash /d/SOUTENANCE/outils-poste/lancer-env.sh`
   - ou depuis GitHub : dépôt `uaa-platform-infra` → *Actions* → **demarrer** → *Run workflow*, puis approuver.
2. **Vérifier que le jeton `GITOPS_TOKEN` est valide** (nécessaire pour la partie 6) :
   une modification de l'API doit faire apparaître un commit « dev → sha-… » dans `uaa-platform-gitops`.
3. **Récupérer les dépôts** sur le poste Ubuntu :

```bash
mkdir -p ~/Bureau/master && cd ~/Bureau/master
for d in uaa-platform-infra uaa-platform-gitops uaa-portal-api; do
  [ -d $d ] && git -C $d pull -q || git clone -q https://github.com/cloudarmelpro/$d.git
done
```

4. **Se connecter à GitHub en ligne de commande** (pour les parties 6 et 7) : `gh auth login`.

### 30 minutes avant

```bash
cd ~/Bureau/master
kubectl config use-context gitops-dev
kubectl get nodes                       # 3 nœuds Ready
kubectl -n argocd get applications      # tout Synced / Healthy
for e in dev staging prod; do curl -s https://$e.elyse-cloud.duckdns.org/api/health; echo " $e"; done
```

Ouvrir à l'avance, dans le navigateur :
- un onglet **ArgoCD** (connecté avec le compte `admin`) ;
- un onglet **GitHub** sur `uaa-portal-api` → *Actions* ;
- un onglet **API prod** : https://prod.elyse-cloud.duckdns.org/api/ ;
- un onglet **Grafana** : https://grafana.elyse-cloud.duckdns.org (connecté avec le compte `admin`).

Préparer **deux terminaux** : un pour les commandes, un pour les `watch`.

---

## Partie 1 — Vue d'ensemble : le code est la source de vérité (2 min)

> **À dire :** « Toute la plateforme est décrite dans trois dépôts Git. Rien n'est fait à la main
> dans la console AWS : l'infrastructure est en Terraform, l'état du cluster est dans un dépôt GitOps,
> et l'application a sa propre chaîne d'intégration continue. »

Montrer sur GitHub les trois dépôts, puis dans le terminal :

```bash
cd ~/Bureau/master
ls uaa-platform-infra/envs/dev/aws        # réseau, cluster EKS, point d'entrée
ls uaa-platform-gitops                     # bootstrap/  platform/  policies/  apps/
ls uaa-platform-gitops/policies/kyverno   # les politiques de sécurité, versionnées
```

---

## Partie 2 — L'infrastructure créée par Terraform (2 min)

> **À dire :** « Le cluster EKS est réparti sur trois zones de disponibilité, dans des sous-réseaux
> privés. Un nœud d'entrée, seul exposé, reçoit le trafic HTTPS. »

```bash
kubectl get nodes -L topology.kubernetes.io/zone,role
aws eks describe-cluster --name gitops-dev --profile uaa --region us-east-1 \
  --query 'cluster.{version:version,statut:status,api_privee:resourcesVpcConfig.endpointPrivateAccess,acces_public_limite_a:resourcesVpcConfig.publicAccessCidrs}'
```

Points à souligner :
- Kubernetes **1.37** en support standard ;
- l'API Kubernetes n'est joignable **que depuis les IP autorisées** (les postes de l'équipe, suivis automatiquement) ;
- l'authentification se fait par **IAM** (aucun fichier de mot de passe Kubernetes).

---

## Partie 3 — GitOps avec ArgoCD (3 min)

> **À dire :** « ArgoCD lit le dépôt `uaa-platform-gitops` et applique en continu ce qui y est décrit.
> Terraform ne fait que l'installer : tout le reste, composants de sécurité compris, vient de Git. »

Dans **ArgoCD** (navigateur) : montrer l'arbre des applications, cliquer sur `portal-api-prod`.

```bash
kubectl -n argocd get applicationsets
kubectl -n argocd get applications
```

Points à souligner :
- **ApplicationSet `applications`** : chaque dossier de `apps/` est déployé automatiquement en dev, staging et prod ;
- les composants (Kyverno, cert-manager, External Secrets, supervision, Traefik) sont activés par des **labels** du cluster (modèle *GitOps Bridge*) ;
- synchronisation **automatique** avec **auto-réparation** (`selfHeal`).

---

## Partie 4 — L'application en ligne, en HTTPS (1 min)

```bash
for e in dev staging prod; do
  echo "== $e"; curl -s https://$e.elyse-cloud.duckdns.org/api/; echo
done
kubectl -n portal-api-prod get deploy,pods,ingress,certificate
```

> **À dire :** « Trois environnements isolés, chacun dans son espace de noms, avec un certificat
> Let's Encrypt obtenu et renouvelé automatiquement par cert-manager. »

Montrer aussi le cadenas dans le navigateur sur https://prod.elyse-cloud.duckdns.org/api/.

---

## Partie 5 — Policy-as-Code : Kyverno bloque ce qui n'est pas conforme (5 min) ★

C'est le cœur du sujet. Prendre son temps.

### 5.1 Les politiques en place

```bash
kubectl get clusterpolicy
```

> **À dire :** « Huit politiques, écrites en YAML et versionnées dans Git : registre d'images autorisé,
> interdiction de `latest`, conteneurs non root, pas de privilèges, pas d'accès à l'hôte, limites de
> ressources obligatoires, système de fichiers en lecture seule. Elles sont en mode **Enforce** :
> une ressource non conforme est refusée avant même d'exister. »

### 5.2 Un pod non conforme est refusé

```bash
kubectl -n portal-api-dev run pirate --image=nginx:latest
```

Résultat attendu : `admission webhook "validate.kyverno.svc-fail" denied the request`, avec la liste
des règles violées (image hors du registre ECR, étiquette `latest`, pas de `runAsNonRoot`,
pas de limites, labels manquants…).

> **À dire :** « Le refus est immédiat, et le message explique au développeur ce qu'il doit corriger. »

### 5.3 Un pod conforme est accepté

```bash
cat > /tmp/conforme.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: demo-conforme
  labels:
    app.kubernetes.io/name: demo
    owner: equipe-plateforme
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
  containers:
    - name: api
      image: 181975986285.dkr.ecr.us-east-1.amazonaws.com/uaa/portal-api:sha-0c141ac
      securityContext:
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: false
        capabilities: { drop: [ALL] }
      resources:
        requests: { cpu: 50m, memory: 64Mi }
        limits: { memory: 128Mi }
EOF
kubectl -n portal-api-dev apply -f /tmp/conforme.yaml --dry-run=server
```

Résultat attendu : `pod/demo-conforme created (server dry run)`.

> **À dire :** « `--dry-run=server` fait passer la requête par tous les contrôles, Kyverno compris,
> sans rien créer : on prouve que la règle laisse passer ce qui est correct. »

### 5.4 Kyverno génère aussi de la sécurité automatiquement

```bash
kubectl -n portal-api-dev get networkpolicy
```

> **À dire :** « Chaque nouvel espace de noms reçoit automatiquement une politique réseau
> « tout refuser par défaut » ; seuls les flux nécessaires sont ouverts. »

### 5.5 Les politiques sont testées comme du code

Montrer sur GitHub : dépôt `uaa-platform-gitops` → *Actions* → workflow **validation** :
à chaque pull request, les politiques sont testées (`kyverno test`) et chaque application est
vérifiée contre les politiques **avant** d'arriver dans le cluster.

---

## Partie 6 — Chaîne complète : du code à la production (6 min) ★

> **À dire :** « Je vais modifier le message de l'API, et vous allez voir la modification arriver en
> ligne sans que je touche au cluster. »

### 6.1 Modifier le code et ouvrir une pull request

```bash
cd ~/Bureau/master/uaa-portal-api
git checkout -b demo-soutenance
sed -i "s/Bonjour depuis la plateforme GitOps de l'Université d'Androy/Bonjour au jury de la soutenance !/" src/main.py
git commit -am "feat: message de démonstration"
git push -u origin demo-soutenance
gh pr create --fill
```

Sur GitHub → *Actions* : montrer les contrôles de la pull request :
**Gitleaks** (secrets), **Semgrep** (code), **Trivy** (dépendances et image).

### 6.2 Fusionner : construction, publication, déploiement en dev

```bash
gh pr checks --watch                 # attendre que tous les contrôles soient verts
gh pr merge --squash --delete-branch
gh run watch --repo cloudarmelpro/uaa-portal-api
```

La CI construit l'image, la publie dans ECR (connexion à AWS **sans clé**, par OIDC), puis écrit la
nouvelle étiquette dans `uaa-platform-gitops`. ArgoCD la déploie en dev.

```bash
kubectl -n portal-api-dev get pods -w        # Ctrl+C quand le nouveau pod est Running
curl -s https://dev.elyse-cloud.duckdns.org/api/; echo
curl -s https://prod.elyse-cloud.duckdns.org/api/; echo   # la prod n'a pas changé
```

### 6.3 Promouvoir en staging puis en production (avec approbation)

```bash
gh workflow run promotion --repo cloudarmelpro/uaa-platform-gitops -f application=portal-api -f vers=staging
```

Puis pour la production :

```bash
gh workflow run promotion --repo cloudarmelpro/uaa-platform-gitops -f application=portal-api -f vers=prod
```

Sur GitHub → *Actions* → **promotion** : la mise en production **attend une approbation**
(*Review deployments* → cocher `prod` → *Approve and deploy*). Seul un approbateur désigné
de l'environnement `prod` (aujourd'hui le compte `cloudarmelpro`) peut le faire : c'est la
séparation des rôles entre celui qui livre et celui qui autorise la mise en production.

```bash
curl -s https://prod.elyse-cloud.duckdns.org/api/; echo
```

> **À dire :** « Chaque passage d'un environnement à l'autre est un commit : on sait qui a déployé
> quoi, quand, et qui l'a approuvé. »

---

## Partie 7 — Retour arrière en une commande (2 min)

> **À dire :** « Si la nouvelle version pose problème, on revient en arrière avec Git. »

```bash
cd ~/Bureau/master/uaa-platform-gitops
git pull -q
git log --oneline -5 -- apps/portal-api/overlays/prod
git revert --no-edit HEAD          # annule le dernier commit (la promotion en prod)
git push
kubectl -n argocd annotate application portal-api-prod argocd.argoproj.io/refresh=normal --overwrite
kubectl -n portal-api-prod get pods -w     # Ctrl+C quand l'ancienne version est Running
curl -s https://prod.elyse-cloud.duckdns.org/api/; echo
```

Vérifier avant le `git revert` que le dernier commit est bien celui de la promotion en prod
(`git log --oneline -1`).

---

## Partie 8 — Auto-réparation : le cluster revient seul à l'état de Git (2 min)

> **À dire :** « Je modifie le cluster à la main, comme le ferait une erreur humaine ou une attaque.
> ArgoCD détecte l'écart et remet l'état décrit dans Git. »

Dans le terminal 2 :

```bash
kubectl -n portal-api-dev get deploy portal-api -w
```

Dans le terminal 1 :

```bash
kubectl -n portal-api-dev scale deploy portal-api --replicas=7
```

Le nombre de réplicas remonte à 7 puis **revient en quelques secondes** à la valeur de Git
(mesure du mémoire : environ 2 secondes).

Autre exemple, plus parlant :

```bash
kubectl -n portal-api-dev delete deploy portal-api
kubectl -n portal-api-dev get deploy,pods        # le déploiement est recréé par ArgoCD
```

---

## Partie 9 — Secrets et supervision (2 min)

### Secrets : jamais dans Git

```bash
kubectl -n portal-api-dev get externalsecret
aws secretsmanager describe-secret --secret-id uaa/dev/portal-api --profile uaa --region us-east-1 \
  --query '{nom:Name,modifie:LastChangedDate}'
grep -r "password\|secret" ~/Bureau/master/uaa-platform-gitops/apps/portal-api/ | head
```

> **À dire :** « Le secret est stocké dans AWS Secrets Manager. External Secrets le copie dans le
> cluster grâce à une identité de pod, sans clé d'accès. Dans Git, il n'y a que la référence. »

### Supervision

Ouvrir https://grafana.elyse-cloud.duckdns.org (utilisateur `admin`). Mot de passe :

```bash
kubectl -n monitoring get secret supervision-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Montrer le tableau de bord **Conformité** (violations des politiques, état des applications ArgoCD),
puis *Explore* → source **Prometheus** pour une requête en direct, par exemple :
`sum by (namespace) (kube_pod_status_phase{phase="Running"})`.

> **À dire :** « Prometheus n'a pas d'authentification : il reste interne au cluster, et on
> l'interroge à travers Grafana, qui, lui, est protégé. »

---

## Partie 10 — Conclusion : vérification globale (1 min)

Depuis le poste Windows (`D:\SOUTENANCE\uaa-plateforme`) :

```bash
bash outils/verifier-plateforme.sh
```

Le script contrôle en une fois : nœuds, applications ArgoCD, politiques en Enforce et sans
violation, secrets synchronisés, supervision, versions déployées par environnement, écarts
d'infrastructure.

> **À dire :** « Tout ce que vous avez vu se reconstruit à l'identique à partir de Git en une
> vingtaine de minutes : c'est la garantie de reproductibilité de l'approche GitOps. »

---

## Après la soutenance

1. Nettoyer la démonstration : remettre le message d'origine par une pull request sur `uaa-portal-api`
   (ou garder le message, au choix).
2. **Arrêter l'environnement** pour ne plus payer (environ 0,45 $ par heure) :
   - depuis le poste Windows : `bash /d/SOUTENANCE/uaa-plateforme/outils/arreter-session.sh` ;
   - ou depuis GitHub : `uaa-platform-infra` → *Actions* → **arreter**, puis approuver.

---

## En cas de problème pendant la démonstration

| Symptôme | Cause probable | Réponse |
|---|---|---|
| `kubectl` : *Unable to connect* ou *i/o timeout* | IP du poste pas encore autorisée (changement de réseau) | attendre 5 minutes (suivi automatique) ; journal `~/.uaa/suivi-ip.log` |
| `kubectl` : *no such host* | coupure DNS passagère | relancer la commande |
| La CI échoue à « Commit et push » (403) | `GITOPS_TOKEN` expiré ou sans droit d'écriture | recréer le jeton (Contents : Read and write sur `uaa-platform-gitops`) |
| Un site répond 503 | pod en cours de démarrage | `kubectl -n portal-api-<env> get pods`, attendre `Running` |
| ArgoCD affiche *OutOfSync* | synchronisation en cours | cliquer *Refresh* ; elle se fait seule en moins de 3 minutes |

**Plan B** si Internet est coupé dans la salle : montrer les captures et les mesures du chapitre 8
du mémoire, et faire la partie 5 en local avec `kyverno test policies/tests/catalogue`
(dans `uaa-platform-gitops`, avec la CLI Kyverno v1.19.2).
