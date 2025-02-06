#!/bin/sh

# Replace BACKEND_URL in config.js
echo "window.APP_CONFIG = { BACKEND_URL: \"$BACKEND_URL\" };" > /app/public/config.js

# Start npm
exec "$@"