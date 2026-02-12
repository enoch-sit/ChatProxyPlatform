# Build stage
FROM node:18-alpine as builder

WORKDIR /usr/src/app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install all dependencies (needed for building)
RUN npm ci || npm install

# Copy source code and TypeScript config
COPY tsconfig.json ./
COPY src ./src

# Debug: Check what files we have
RUN echo "=== Files before build ===" && ls -la && echo "=== Source files ===" && ls -la src/

# Build TypeScript code
RUN npm run build

# Debug: Check build output
RUN echo "=== Files after build ===" && ls -la && echo "=== Dist directory ===" && (ls -la dist/ || echo "No dist directory") && echo "=== Dist/src directory ===" && (ls -la dist/src/ || echo "No dist/src directory")

# Production stage
FROM node:18-alpine

WORKDIR /usr/src/app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install ONLY production dependencies
RUN npm ci --omit=dev || npm install --production

# Copy built files from builder stage
COPY --from=builder /usr/src/app/dist ./dist

# Debug: Check what was copied
RUN echo "=== Production stage files ===" && ls -la && echo "=== Dist in production ===" && (ls -la dist/ || echo "No dist directory") && echo "=== Dist/src in production ===" && (ls -la dist/src/ || echo "No dist/src directory")

# Create logs directory
RUN mkdir -p logs

# Expose port
EXPOSE 3001

# Set environment variables
ENV NODE_ENV=production

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:3001/health || exit 1

# Start the service with the correct path to the compiled server.js
CMD ["node", "dist/src/server.js"]