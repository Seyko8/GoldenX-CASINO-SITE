# --- Composer stage ---
FROM composer:2 AS composer_build
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --prefer-dist --no-scripts --no-progress
COPY . .
RUN composer dump-autoload --optimize

# --- Node assets (optional, falls vorhanden) ---
FROM node:20-alpine AS node_build
WORKDIR /app
COPY package.json package-lock.json* yarn.lock* ./
RUN [ -f package.json ] && (npm ci || true)
COPY . .
RUN [ -f package.json ] && (npm run build || true)

# --- Runtime (php-fpm) ---
FROM php:8.2-fpm-alpine
WORKDIR /var/www/html
RUN apk add --no-cache nginx supervisor bash git curl libpng libjpeg-turbo freetype libzip \
    && docker-php-ext-install pdo pdo_mysql bcmath opcache

COPY --from=composer_build /app /var/www/html
COPY --from=node_build /app/public /var/www/html/public
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

COPY nginx.conf /etc/nginx/nginx.conf

CMD bash -lc '\
  cp -n .env.example .env && \
  php artisan key:generate && \
  php artisan migrate --force || true && \
  php artisan storage:link || true && \
  php-fpm -D && \
  nginx -g "daemon off;" \
'