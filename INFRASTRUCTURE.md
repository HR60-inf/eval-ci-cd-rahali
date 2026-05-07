# INFRASTRUCTURE.md — Mission CI/CD QuickNotes

**Étudiant :** Ismael RAHALI  
**Promotion :** EPF 3ᵉ année Cyber 2026  
**Date :** 07/05/2026

---

## 1. Schéma d'architecture

```
┌──────────────┐     git push      ┌──────────────┐
│  Poste dev   │ ─────────────────▶│   GitHub     │
│  (local)     │                   │ (repo privé) │
└──────────────┘                   └──────┬───────┘
                                          │ pollSCM (1 min)
                                          ▼
                                   ┌──────────────┐
                                   │   Jenkins    │◀── Docker Desktop (local)
                                   │  (Docker)    │
                                   └──────┬───────┘
                                          │
                         ┌────────────────┼────────────────┐
                         │                │                │
                         ▼                ▼                ▼
                   ┌──────────┐    ┌──────────┐    ┌──────────────┐
                   │node:18   │    │semgrep/  │    │   Discord    │
                   │-alpine   │    │semgrep   │    │  (webhook)   │
                   │(CI stages│    │(SAST)    │    │ notifications│
                   └──────────┘    └──────────┘    └──────────────┘
                                          │
                                          │ Deploy Hook (curl)
                                          ▼
                                   ┌──────────────┐
                                   │   Render.com │
                                   │ (Web Service │
                                   │   Docker)    │
                                   └──────────────┘
```

**Flux résumé :**
1. Le développeur pousse le code sur GitHub
2. Jenkins détecte le changement via `pollSCM` (toutes les minutes)
3. La pipeline s'exécute dans des conteneurs Docker isolés
4. Discord reçoit la notification de succès/échec
5. Après validation manuelle, Render déploie via Deploy Hook

---

## 2. Procédure d'installation reproductible

### 2.1 Lancer Jenkins dans Docker

```bash
# Lancer Jenkins avec accès au daemon Docker de l'hôte
docker run -d \
  --name jenkins \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -u root \
  jenkins/jenkins:lts-jdk17

# Installer Docker CLI et curl dans le conteneur Jenkins
docker exec jenkins bash -c "apt-get update -qq && apt-get install -y docker.io curl"
```

### 2.2 Récupérer le mot de passe admin initial

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

### 2.3 Configuration initiale Jenkins (UI)

1. Ouvrir `http://localhost:8080`
2. Coller le mot de passe initial
3. Choisir **"Install suggested plugins"**
4. Créer un compte administrateur
5. Installer les plugins supplémentaires via **Manage Jenkins → Plugins** :
   - **Docker Pipeline** (pour `agent { docker { ... } }`)
   - **Git** (normalement déjà présent)

### 2.4 Configurer les credentials

Aller dans **Manage Jenkins → Credentials → System → Global credentials → Add Credentials** :

| ID | Type | Valeur |
|----|------|--------|
| `github-token` | Username with password | Votre token GitHub (Settings → Developer Settings → Personal Access Tokens → Fine-grained) |
| `render-deploy-hook` | Secret text | L'URL du Deploy Hook Render (voir section 2.5) |

### 2.5 Obtenir le Deploy Hook Render

1. Se connecter sur [render.com](https://render.com)
2. Créer un **New Web Service** → connecter le repo GitHub `eval-ci-cd-rahali`
3. Sélectionner **Language: Docker** (important !)
4. Une fois créé : **Settings → Deploy Hook** → copier l'URL
5. Ajouter cette URL dans Jenkins credentials (ID: `render-deploy-hook`)

### 2.6 Créer le job Jenkins

1. **New Item → Pipeline**
2. Nom : `quicknotes-cicd`
3. Section **Pipeline** :
   - Definition: **Pipeline script from SCM**
   - SCM: **Git**
   - Repository URL: `https://github.com/<votre-username>/eval-ci-cd-rahali.git`
   - Credentials: `github-token`
   - Branch: `*/main`
   - Script Path: `Jenkinsfile`
4. Sauvegarder

---

## 3. Description de chaque stage du Jenkinsfile

| Stage | Description |
|-------|-------------|
| **Checkout** | Récupère le code source depuis GitHub via `checkout scm`. Point d'entrée obligatoire de toute pipeline. |
| **Install** | Exécute `npm ci` pour installer les dépendances exactes du `package-lock.json`. Plus reproductible que `npm install` car il ne met pas à jour les versions. |
| **Lint** | Lance `npm run lint` (ESLint) pour détecter les erreurs syntaxiques et les non-conformités de style avant d'aller plus loin. |
| **Tests** | Exécute les tests unitaires Jest. Valide que le code fonctionne correctement avant toute analyse de sécurité. |
| **Coverage** | Vérifie que la couverture de code dépasse 70% (lignes et fonctions). Jest échoue avec un code d'erreur si le seuil n'est pas atteint. |
| **SCA** | `npm audit --audit-level=high` : analyse les dépendances NPM contre la base CVE. Bloque la pipeline si une vulnérabilité HIGH ou CRITICAL est trouvée. |
| **SAST** | Semgrep avec `--config=auto` analyse le code source à la recherche de failles (XSS, path traversal, secrets hardcodés, injections). Conteneur Docker dédié isolé. |
| **Deploy** | Après validation manuelle (`input`), déclenche le déploiement sur Render via un Deploy Hook (requête HTTP POST). |
| **Notifications** | En cas d'échec ou de succès, envoie un message Discord via webhook contenant le nom du job, le numéro de build, l'étudiant et le lien Jenkins. |

---

## 4. Choix techniques justifiés

### 4.1 pollSCM vs build manuel

**Choix : `pollSCM('* * * * *')`** (vérification toutes les minutes)

**Justification :** Jenkins tourne sur le poste local sans adresse IP publique. Un webhook GitHub → Jenkins est donc impossible (GitHub ne peut pas joindre `localhost:8080`). Entre build manuel et `pollSCM`, j'ai choisi `pollSCM` car il est plus proche d'une vraie CI automatisée : dès qu'un commit est détecté sur `main`, la pipeline se déclenche automatiquement sans intervention humaine. La latence d'une minute est acceptable pour un contexte d'évaluation.

### 4.2 Seuil de coverage : 70%

**Choix : 70% lignes et fonctions, 60% branches**

**Justification :** Les tests fournis couvrent tous les endpoints CRUD et la recherche. 70% est un standard industrie raisonnable pour une API REST en phase initiale. Un seuil plus élevé (90%+) serait pertinent en production mais irréaliste en 4h. 60% pour les branches reflète que certaines conditions d'erreur (ex: fichier export inexistant) sont difficiles à tester sans fixture.

### 4.3 Outil SAST : Semgrep

**Choix : `semgrep/semgrep` avec `--config=auto`**

**Justification :** Semgrep est open-source, disponible en image Docker officielle, et ses règles `auto` couvrent JavaScript/Node.js/Express avec des règles spécifiques pour XSS, path traversal et secrets. Alternative évaluée : ESLint security plugin (déjà présent mais moins puissant). Semgrep a été préféré car il opère sur l'AST (arbre syntaxique) et produit moins de faux positifs.

### 4.4 Question d'architecture — Isolation entre stages

**Problème :** Jenkins tourne dans un seul conteneur. Comment éviter qu'un stage pollue l'environnement du suivant ?

**Solution implémentée :** Chaque stage utilise `agent { docker { image '...'; reuseNode true } }`.

**Explication :** Chaque stage est exécuté dans un conteneur Docker **distinct et éphémère** :
- Le stage `Tests` s'exécute dans `node:18-alpine` → son environnement Node.js est entièrement isolé
- Le stage `SAST` s'exécute dans `semgrep/semgrep` → aucun accès aux binaires Node.js ni aux `node_modules` du stage précédent
- `reuseNode true` permet de partager le **workspace** (les fichiers du repo) entre stages sur le disque hôte, sans partager l'environnement d'exécution (PATH, libs installées, variables d'env du conteneur)
- Chaque build repart d'une image Docker fraîche → reproductibilité garantie

---

## 5. Synthèse manager — Ce que la pipeline garantit

*À destination du CTO de QuickNotes (non-technique)*

Avant mon intervention, le code de QuickNotes était déployé manuellement, sans aucun filet de sécurité. Un développeur pouvait pousser du code bugué ou contenant des failles directement en production.

**La pipeline CI/CD que j'ai mise en place garantit automatiquement, à chaque modification du code :**

1. **Que le code est propre** : vérification syntaxique automatique (Lint)
2. **Que le code fonctionne** : les tests automatisés valident les fonctionnalités principales
3. **Que le code est suffisamment testé** : au moins 70% du code est couvert par des tests
4. **Que les bibliothèques utilisées ne sont pas vulnérables** : analyse automatique des dépendances (SCA)
5. **Que le code lui-même ne contient pas de failles** : analyse statique de sécurité (SAST) détectant XSS, injection, secrets exposés
6. **Qu'aucun déploiement ne se fait sans validation humaine** : un responsable doit approuver avant que le code parte en production
7. **Que l'équipe est notifiée en temps réel** : Discord reçoit une alerte immédiate en cas d'échec ou de succès

En résumé : si la pipeline est verte, vous avez l'assurance que le code livré est propre, testé et sécurisé. Si elle est rouge, personne n'arrive en production et l'équipe est notifiée immédiatement.
