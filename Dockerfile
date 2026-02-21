# v0.8.3-rc1

# Base node image (This is the "node" stage)
FROM node:20-alpine AS node

# Install common dependencies needed for LibreChat's build process
RUN apk add --no-cache jemalloc
RUN apk add --no-cache python3 py3-pip uv

# Set environment variable to use jemalloc
ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2

# Add `uv` for extended MCP support
COPY --from=ghcr.io/astral-sh/uv:0.9.5-python3.12-alpine /usr/local/bin/uv /usr/local/bin/uvx /bin/
RUN uv --version

# Set configurable max-old-space-size with default
ARG NODE_MAX_OLD_SPACE_SIZE=6144

# Create app directory and set ownership
RUN mkdir -p /app && chown node:node /app
WORKDIR /app

USER node

# Copy package.json files to leverage Docker caching for npm install
COPY --chown=node:node package.json package-lock.json ./
COPY --chown=node:node api/package.json ./api/package.json
COPY --chown=node:node client/package.json ./client/package.json
COPY --chown=node:node packages/data-provider/package.json ./packages/data-provider/package.json
COPY --chown=node:node packages/data-schemas/package.json ./packages/data-schemas/package.json
COPY --chown=node:node packages/api/package.json ./packages/api/package.json

# --- START: Debug and LibreChat.yaml Insertion ---
# DEBUG: List files in the current build context (Keep for one more test to verify .dockerignore fix)
RUN ls -l

# Copy LibreChat configuration file into the app directory
COPY --chown=node:node librechat.yaml /app/librechat.yaml
# --- END: Debug and LibreChat.yaml Insertion ---


# Run npm install and client build steps
RUN \
    # Allow mounting of these files, which have no default
    touch .env ; \
    # Create directories for the volumes to inherit the correct permissions
    mkdir -p /app/client/public/images /app/logs /app/uploads ; \
    npm config set fetch-retry-maxtimeout 600000 ; \
    npm config set fetch-retries 5 ; \
    npm config set fetch-retry-mintimeout 15000 ; \
    npm ci --no-audit

# Copy all other application files
COPY --chown=node:node . .

RUN \
    # React client build with configurable memory
    NODE_OPTIONS="--max-old-space-size=${NODE_MAX_OLD_SPACE_SIZE}" npm run frontend; \
    npm prune --production; \
    npm cache clean --force

# Node API setup
EXPOSE 3080
ENV HOST=0.0.0.0
CMD ["npm", "run", "backend"]

# Optional: for client with nginx routing (keeping this commented out)
# FROM nginx:stable-alpine AS nginx-client
# WORKDIR /usr/share/nginx/html
# COPY --from=node /app/client/dist /usr/share/nginx/html
# COPY client/nginx.conf /etc/nginx/conf.d/default.conf
# ENTRYPOINT ["nginx", "-g", "daemon off;"]
