# ============================================
# Auth Service - Development Dockerfile
# ============================================
# Optimized for hot-reloading and development

FROM node:18-alpine

WORKDIR /app

# Install build dependencies for native modules
RUN apk add --no-cache python3 make g++

# Copy package files first for better caching
COPY package.json package-lock.json ./

# Install all dependencies (including dev dependencies)
RUN npm ci || npm install

# Copy application code
COPY . .

# Expose application port
EXPOSE 3000

# Start development server with hot-reloading
CMD ["npm", "run", "dev"]
