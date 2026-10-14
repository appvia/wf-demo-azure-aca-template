# The hello-world page this service serves. nginx-unprivileged listens on 8080
# and runs as uid 101, so the container never needs root at runtime.
FROM nginxinc/nginx-unprivileged:1.27-alpine

# The greeting on the page. Edit this one line, open a pull request, and the
# preview shows the new text.
ENV GREETING="Hello from Wayfinder"

# The release label is NOT baked in: production runs the exact image built for
# develop, so the release is read from APP_RELEASE when the container starts.
# The nginx entrypoint runs every executable /docker-entrypoint.d/*.sh first.
USER root
COPY docker/40-render-index.sh /docker-entrypoint.d/40-render-index.sh
RUN chmod 0755 /docker-entrypoint.d/40-render-index.sh \
    && chown -R 101 /usr/share/nginx/html
USER 101

EXPOSE 8080
