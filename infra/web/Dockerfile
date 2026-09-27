# Web image for staging (M1-FOU-012): serves the three Flutter web apps and proxies the API.
#   /platform/  /billing/  /hrms/   -> Flutter builds (built by infra/web/build-web.sh)
#   /api/  /health                  -> backend container
# Runs as the unprivileged nginx user on port 8080.
FROM nginxinc/nginx-unprivileged:1.30.5-alpine

COPY infra/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY apps/platform/build/web /usr/share/nginx/html/platform
COPY apps/billing/build/web  /usr/share/nginx/html/billing
COPY apps/hrms/build/web     /usr/share/nginx/html/hrms

EXPOSE 8080
