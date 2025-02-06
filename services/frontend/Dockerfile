# Base image for Node.js
FROM node:18-slim

# Set the working directory
WORKDIR /app

# Copy the frontend files
COPY app/ /app

# Install dependencies
RUN npm install

# Build the React app for production
RUN npm run build

# Use a lightweight web server for serving static files
FROM nginx:alpine

# Copy the built files to the nginx web server
COPY --from=0 /app/build /usr/share/nginx/html

# Expose the frontend port
EXPOSE 80

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]