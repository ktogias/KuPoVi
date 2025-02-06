#!/bin/sh

# Replace BACKEND_URL in config.js
echo "window.APP_CONFIG = { BACKEND_URL: \"$BACKEND_URL\" };" > /usr/share/nginx/html/config.js

# Start Nginx
exec "$@"