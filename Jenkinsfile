pipeline {
    agent any

    triggers {
        // pollSCM : vérifie le repo toutes les minutes.
        // Choix justifié : Jenkins tourne en local sans IP publique,
        // donc un webhook GitHub entrant est impossible.
        // pollSCM est plus automatisé qu'un build manuel et suffit pour la CI.
        pollSCM('* * * * *')
    }

    environment {
        DISCORD_WEBHOOK = 'https://discord.com/api/webhooks/1500795940305506416/6xfZiyqKvPMA08jWQUFlPT9i1nOPJFShYeP4ju3n0-i1kShM0HVUHfvNUH_NptPOCVFI'
        STUDENT         = 'Ismael RAHALI'
    }

    stages {

        // ─────────────────────────────────────────────
        // STAGE 1 — Checkout
        // Récupère le code source depuis GitHub via SCM.
        // ─────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 2 — Install
        // Installe les dépendances de manière reproductible via npm ci
        // (plus strict que npm install : respecte exactement le package-lock.json).
        // Isolation : conteneur node:18-alpine fresh à chaque build.
        // ─────────────────────────────────────────────
        stage('Install') {
            agent { docker { image 'node:18-alpine'; reuseNode true } }
            steps {
                sh 'npm ci'
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 3 — Lint
        // Vérifie la qualité syntaxique et stylistique du code via ESLint.
        // Bloque la pipeline si le code ne respecte pas les règles définies.
        // ─────────────────────────────────────────────
        stage('Lint') {
            agent { docker { image 'node:18-alpine'; reuseNode true } }
            steps {
                sh 'npm run lint'
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 4 — Tests
        // Exécute les tests unitaires avec Jest.
        // Isolation garantie : conteneur node:18-alpine distinct du stage SAST.
        // ─────────────────────────────────────────────
        stage('Tests') {
            agent { docker { image 'node:18-alpine'; reuseNode true } }
            steps {
                sh 'npm test'
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 5 — Coverage
        // Vérifie que la couverture de code dépasse le seuil minimal de 70% (lignes).
        // Seuil choisi : 70% est un standard industrie raisonnable pour une API REST.
        // Jest échoue avec code 1 si le seuil n'est pas atteint.
        // ─────────────────────────────────────────────
        stage('Coverage') {
            agent { docker { image 'node:18-alpine'; reuseNode true } }
            steps {
                sh '''npx jest --coverage --coverageThreshold='{"global":{"lines":70,"functions":70,"branches":60}}'
                '''
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 6 — SCA (Software Composition Analysis)
        // Analyse les dépendances NPM à la recherche de vulnérabilités connues (CVE).
        // npm audit --audit-level=high fait échouer la pipeline si une vuln HIGH ou
        // CRITICAL est détectée. Outil natif npm, aucune dépendance supplémentaire.
        // ─────────────────────────────────────────────
        stage('SCA') {
            agent { docker { image 'node:18-alpine'; reuseNode true } }
            steps {
                sh 'npm audit --audit-level=high'
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 7 — SAST (Static Application Security Testing)
        // Analyse statique du code source avec Semgrep.
        // Détecte : XSS, path traversal, secrets hardcodés, injections.
        // Conteneur semgrep/semgrep isolé → aucune contamination par node_modules.
        // ─────────────────────────────────────────────
        stage('SAST') {
            agent { docker { image 'semgrep/semgrep'; reuseNode true } }
            steps {
                sh 'semgrep --config=auto --error src/'
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 8 — Deploy
        // Déploiement sur Render via Deploy Hook après validation manuelle.
        // La validation manuelle (input) garantit qu'un humain valide avant prod.
        // ─────────────────────────────────────────────
        stage('Deploy') {
            steps {
                input message: '🚀 Déployer en production sur Render ?', ok: 'Déployer !'
                withCredentials([string(credentialsId: 'render-deploy-hook', variable: 'RENDER_HOOK')]) {
                    sh 'curl -s -X POST "$RENDER_HOOK"'
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // NOTIFICATIONS DISCORD
    // Envoi automatique en cas d'échec ET de succès.
    // Le message contient : nom du job, numéro de build, étudiant, lien Jenkins.
    // ─────────────────────────────────────────────
    post {
        failure {
            script {
                def payload = """{
                    "content": "❌ **ÉCHEC PIPELINE** — Job: **${env.JOB_NAME}** Build #${env.BUILD_NUMBER}\\nÉtudiant: **${env.STUDENT}**\\n🔗 ${env.BUILD_URL}"
                }"""
                writeFile file: 'discord_fail.json', text: payload
                sh "curl -s -X POST '${DISCORD_WEBHOOK}' -H 'Content-Type: application/json' -d @discord_fail.json"
            }
        }
        success {
            script {
                def payload = """{
                    "content": "✅ **SUCCÈS PIPELINE** — Job: **${env.JOB_NAME}** Build #${env.BUILD_NUMBER}\\nÉtudiant: **${env.STUDENT}**\\n🔗 ${env.BUILD_URL}"
                }"""
                writeFile file: 'discord_success.json', text: payload
                sh "curl -s -X POST '${DISCORD_WEBHOOK}' -H 'Content-Type: application/json' -d @discord_success.json"
            }
        }
    }
}
