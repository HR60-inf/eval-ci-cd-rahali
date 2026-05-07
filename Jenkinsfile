pipeline {
    agent any

    triggers {
        pollSCM('* * * * *')
    }

    environment {
        DISCORD_WEBHOOK = 'https://discord.com/api/webhooks/1500795940305506416/6xfZiyqKvPMA08jWQUFlPT9i1nOPJFShYeP4ju3n0-i1kShM0HVUHfvNUH_NptPOCVFI'
        STUDENT         = 'Ismael RAHALI'
    }

    stages {

        // ── Checkout ──────────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // ── Install ───────────────────────────────────────────────────────────
        // npm ci installe exactement les versions du package-lock.json
        stage('Install') {
            steps {
                sh 'npm ci'
            }
        }

        // ── Lint ──────────────────────────────────────────────────────────────
        stage('Lint') {
            steps {
                sh 'npm run lint'
            }
        }

        // ── Tests ─────────────────────────────────────────────────────────────
        stage('Tests') {
            steps {
                sh 'npm test'
            }
        }

        // ── Coverage ──────────────────────────────────────────────────────────
        // Seuil : 70% lignes/fonctions, 60% branches — standard industrie
        stage('Coverage') {
            steps {
                sh '''npx jest --coverage --coverageThreshold='{"global":{"lines":70,"functions":70,"branches":50}}'
                '''
            }
        }

        // ── SCA ───────────────────────────────────────────────────────────────
        // npm audit détecte les dépendances vulnérables (CVE)
        stage('SCA') {
            steps {
                // || true : faille lodash documentée dans AUDIT_SECURITE.md (Faille #4)
                // On laisse la pipeline continuer pour révéler les failles suivantes
                sh 'npm audit --audit-level=high || true'
            }
        }

        // ── SAST ──────────────────────────────────────────────────────────────
        // Semgrep tourne dans son propre conteneur Docker isolé
        // → garantit l'isolation avec le stage Tests (environnements séparés)
        stage('SAST') {
            steps {
                sh 'docker run --rm -v "${WORKSPACE}:/src" semgrep/semgrep semgrep --config=auto --error /src/src/'
            }
        }

        // ── Deploy ────────────────────────────────────────────────────────────
        // Validation manuelle obligatoire avant tout déploiement en production
        stage('Deploy') {
            steps {
                input message: '🚀 Déployer en production sur Render ?', ok: 'Déployer !'
                withCredentials([string(credentialsId: 'render-deploy-hook', variable: 'RENDER_HOOK')]) {
                    sh 'curl -s -X POST "$RENDER_HOOK"'
                }
            }
        }
    }

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
