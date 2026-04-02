# Multi-stage build for React app
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Accept build-time env vars for Vite (baked into the static bundle)
ARG VITE_FLOWISE_PROXY_API_URL=https://aidcec-ai-agent.com
ENV VITE_FLOWISE_PROXY_API_URL=$VITE_FLOWISE_PROXY_API_URL

# Copy package files
COPY package*.json ./

# Install all dependencies (including dev dependencies needed for build)
RUN npm ci

# Copy source code
COPY . .

# Build the app
RUN npm run build

# Production stage
FROM nginx:alpine

# Install wget for healthcheck
RUN apk add --no-cache wget

# Copy built app from builder stage
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Expose port
EXPOSE 3082

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
