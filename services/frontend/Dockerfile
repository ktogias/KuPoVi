# ====== Development Image ======
FROM node:18-slim AS dev

WORKDIR /app

# Copy package files first (for caching layers)
COPY app/package.json app/package-lock.json ./

# Install dependencies only in dev
RUN npm install

# Copy the rest of the app
COPY app/ .

# Inject runtime environment variables
COPY target/dev/ /
RUN chmod +x /docker-entrypoint.sh

# Expose port for development
EXPOSE 3000

ENTRYPOINT ["/docker-entrypoint.sh"]

# Start React development server
CMD ["npm", "start"]


# ====== Production Image ======
FROM node:18-slim AS build

WORKDIR /app

# Copy package files and install production dependencies
COPY app/package.json app/package-lock.json ./
RUN npm install --production

# Copy the rest of the app
COPY app/ .

# Build the React app
RUN npm run build


# ====== Nginx Production Server ======
FROM nginx:alpine AS prod

# Copy only the build files from the build stage
COPY --from=build /app/build /usr/share/nginx/html

# Inject runtime environment variables
COPY target/prod/ /
RUN chmod +x /docker-entrypoint.sh

# Expose frontend port
EXPOSE 80

ENTRYPOINT ["/docker-entrypoint.sh"]
# Start Nginx
CMD ["nginx", "-g", "daemon off;"]