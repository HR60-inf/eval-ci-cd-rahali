# ── Étape 1 : image de base légère Node.js 18 LTS ──────────────────────────
FROM node:18-alpine

# Répertoire de travail dans le conteneur
WORKDIR /app

# ── Étape 2 : dépendances (couche cachée séparément pour les rebuilds) ───────
COPY package*.json ./
RUN npm ci --omit=dev

# ── Étape 3 : code source de l'application ───────────────────────────────────
COPY src/ ./src/

# ── Port exposé (Render utilise la variable PORT automatiquement) ─────────────
EXPOSE 3000

# ── Health check natif Docker ──────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# ── Commande de démarrage ──────────────────────────────────────────────────────
CMD ["node", "src/app.js"]
