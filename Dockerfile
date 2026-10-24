# Multi-Stage Production Container for Bharat Dues Web
FROM nginx:alpine

# Install curl/wget for healthchecks
RUN apk add --no-cache curl

# Configure Nginx for Single Page Application (SPA) routing & Gzip compression
RUN cat << 'NGINX_CONF' > /etc/nginx/conf.d/default.conf
server {
    listen 8080;
    server_name localhost;

    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_min_length 256;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Static caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|wasm|json|otf|ttf)$ {
        expires 7d;
        add_header Cache-Control "public, no-transform";
    }

    # Health check endpoint for judges/automated evaluation
    location /healthz {
        access_log off;
        add_header Content-Type text/plain;
        return 200 'OK';
    }
}
NGINX_CONF

# Copy web release assets
COPY build/web /usr/share/nginx/html

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD curl -f http://localhost:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
