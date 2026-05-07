# AUDIT_SECURITE.md — Rapport d'audit de sécurité QuickNotes

**Étudiant :** Ismael RAHALI  
**Promotion :** EPF 3ᵉ année Cyber 2026  
**Date :** 07/05/2026  
**Outils utilisés :** Semgrep (SAST), npm audit (SCA)

---

> **Rappel de contexte :** Les failles ci-dessous ont été **détectées par la pipeline CI/CD**. Conformément aux instructions du sujet, aucune correction n'a été apportée au code. Le rôle du consultant est ici de détecter et documenter, pas de corriger.

---

## Faille #1 — XSS Reflétée (Cross-Site Scripting)

| Champ | Détail |
|-------|--------|
| **Type** | XSS Reflétée (Reflected Cross-Site Scripting) |
| **Localisation** | `src/routes.js` — endpoint `GET /api/search` |
| **Outil détecteur** | Semgrep (`--config=auto`) |
| **Extrait du code vulnérable** | `<h1>Résultats pour : ${q}</h1>` — la variable `q` provient directement de `req.query.q` sans aucun échappement |
| **Extrait du log Semgrep** | `[ERROR] javascript.express.security.audit.express-xss: Detected user input used directly in HTML response` |
| **Criticité** | 🔴 **Haute** |
| **Justification** | Un attaquant peut forger une URL du type `/api/search?q=<script>alert(document.cookie)</script>` et partager ce lien à un administrateur. Quand l'admin clique, le script s'exécute dans son navigateur, permettant le vol de session (cookie), la redirection vers un faux site, ou l'exécution d'actions en son nom. |
| **Remédiation recommandée** | Utiliser la bibliothèque `escape-html` pour échapper le paramètre avant de l'injecter dans le HTML : `const escapeHtml = require('escape-html'); ...${escapeHtml(q)}...`. Alternative : migrer vers un moteur de templates avec auto-escape (Pug, Handlebars). |

📸 *Capture à insérer :* `screenshots/02-sast-xss-fail.png` — Pipeline Overview Jenkins avec stage SAST en rouge

---

## Faille #2 — Path Traversal (Directory Traversal)

| Champ | Détail |
|-------|--------|
| **Type** | Path Traversal / Directory Traversal |
| **Localisation** | `src/routes.js` — endpoint `GET /api/export` |
| **Outil détecteur** | Semgrep (`--config=auto`) |
| **Extrait du code vulnérable** | `const fullPath = path.join(config.exportDir, file)` où `file` vient de `req.query.file` sans validation ni sanitisation |
| **Extrait du log Semgrep** | `[ERROR] javascript.lang.security.audit.path-traversal.path-join-resolve-traversal: Detected user input in path operation` |
| **Criticité** | 🔴 **Haute** |
| **Justification** | Un attaquant peut envoyer `GET /api/export?file=../../etc/passwd` pour lire des fichiers arbitraires sur le serveur. Sur un serveur Linux, cela peut exposer les fichiers de configuration système, les clés SSH, ou d'autres données sensibles. |
| **Remédiation recommandée** | Valider que le chemin résolu reste dans le répertoire autorisé : `const resolved = path.resolve(config.exportDir, file); if (!resolved.startsWith(path.resolve(config.exportDir))) return res.status(400).json({error: 'invalid path'});`. Utiliser également une liste blanche des noms de fichiers autorisés. |

📸 *Capture à insérer :* `screenshots/03-sast-path-traversal-fail.png` — Pipeline Overview Jenkins avec stage SAST en rouge

---

## Faille #3 — Secret Hardcodé (Hardcoded Secret)

| Champ | Détail |
|-------|--------|
| **Type** | Secret / Credential Hardcodé dans le code source |
| **Localisation** | `src/config.js` — ligne 8 |
| **Outil détecteur** | Semgrep (`--config=auto`) |
| **Extrait du code vulnérable** | `ADMIN_TOKEN: 'qn_admin_2026_S3cr3t!'` — token administrateur en clair dans le fichier de configuration |
| **Extrait du log Semgrep** | `[ERROR] generic.secrets.security.detected-generic-secret: Detected a hardcoded secret` |
| **Criticité** | 🔴 **Haute** |
| **Justification** | Le token `qn_admin_2026_S3cr3t!` est visible dans le code source. Si le dépôt GitHub est un jour rendu public (par erreur ou après un départ d'employé), n'importe qui peut utiliser ce token pour appeler `POST /api/admin/purge` et effacer toutes les notes en base. De plus, même dans un repo privé, le secret est visible par tous les développeurs ayant accès. |
| **Remédiation recommandée** | Stocker le secret dans une variable d'environnement : `ADMIN_TOKEN: process.env.ADMIN_TOKEN`. Sur Render, définir la variable dans **Environment** → **Environment Variables**. Ne jamais versionner de secrets dans Git. |

📸 *Capture à insérer :* `screenshots/04-sast-secret-fail.png` — Pipeline Overview Jenkins avec stage SAST en rouge

---

## Faille #4 — Dépendance Vulnérable : Lodash 4.17.4 (SCA)

| Champ | Détail |
|-------|--------|
| **Type** | Vulnerable Dependency / Supply Chain Attack |
| **Localisation** | `package.json` — `"lodash": "4.17.4"` |
| **Outil détecteur** | `npm audit` (SCA — Software Composition Analysis) |
| **CVE associés** | CVE-2019-10744 (Prototype Pollution — High), CVE-2020-8203 (Prototype Pollution — High), CVE-2021-23337 (Command Injection — High) |
| **Extrait du log npm audit** | `lodash  <=4.17.20 → Severity: high → Prototype Pollution` |
| **Criticité** | 🔴 **Haute** |
| **Justification** | La version `4.17.4` de lodash est affectée par plusieurs vulnérabilités de type **Prototype Pollution**. Un attaquant peut envoyer un payload JSON spécialement forgé pour modifier le prototype des objets JavaScript globaux, ce qui peut aboutir à une exécution de code arbitraire côté serveur ou à des contournements de logique métier. |
| **Remédiation recommandée** | Mettre à jour lodash vers la version `4.17.21` minimum : `npm update lodash`. Vérifier également si lodash est réellement nécessaire (seul `_.pick` est utilisé, fonctionnalité remplaçable nativement). |

📸 *Capture à insérer :* `screenshots/05-sca-lodash-fail.png` — Pipeline Overview Jenkins avec stage SCA en rouge

---

## Faille #5 (BONUS) — Scan de secrets dans l'historique Git (Trufflehog)

| Champ | Détail |
|-------|--------|
| **Type** | Secret exposé dans l'historique Git |
| **Localisation** | Historique du dépôt Git (commits) |
| **Outil détecteur** | **Trufflehog** (`trufflesecurity/trufflehog`) — outil non listé dans le sujet |
| **Commande utilisée** | `docker run --rm trufflesecurity/trufflehog:latest git file://. --only-verified` |
| **Criticité** | 🟠 **Moyenne à Haute** |
| **Justification** | Même si le secret `qn_admin_2026_S3cr3t!` est retiré du code (faille #3 corrigée), il peut rester présent dans l'**historique Git** des commits précédents. Trufflehog scanne l'intégralité de l'historique et détecte les secrets qui ont été commités à un moment donné, même s'ils ont été supprimés depuis. Un attaquant ayant accès au repo peut retrouver le secret via `git log`. |
| **Remédiation recommandée** | 1. Révoquer immédiatement le token compromis. 2. Utiliser `git filter-branch` ou `git-filter-repo` pour réécrire l'historique et supprimer le secret. 3. Mettre en place un pre-commit hook avec `detect-secrets` pour éviter que des secrets soient commités à l'avenir. |

📸 *Capture à insérer :* `screenshots/06-trufflehog-secrets.png` — Output de Trufflehog dans Jenkins

---

## Synthèse des failles détectées

| # | Type | Fichier | Outil | Criticité |
|---|------|---------|-------|-----------|
| 1 | XSS Reflétée | `src/routes.js` | Semgrep | 🔴 Haute |
| 2 | Path Traversal | `src/routes.js` | Semgrep | 🔴 Haute |
| 3 | Secret Hardcodé | `src/config.js` | Semgrep | 🔴 Haute |
| 4 | Dépendance vulnérable (lodash) | `package.json` | npm audit | 🔴 Haute |
| 5 (bonus) | Secret en historique Git | Git history | Trufflehog | 🟠 Moyenne |

**Conclusion :** Le projet QuickNotes présente **4 vulnérabilités de niveau Haute** et 1 vulnérabilité de niveau Moyen détectées automatiquement par la pipeline. Aucune de ces failles ne nécessitait une expertise avancée pour être exploitée. Elles auraient pu avoir des conséquences graves en production (vol de données, suppression de la base, accès non autorisé aux fichiers serveur). La mise en place de cette pipeline CI/CD aurait permis de les détecter dès les premiers commits.
