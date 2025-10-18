FROM kong:3.6

# Install custom plugins
USER root

# Copy unkey-auth plugin (build context is project root)
COPY services/kong-plugins/unkey-auth /usr/local/share/lua/5.1/kong/plugins/unkey-auth

# Ensure proper permissions
RUN chown -R kong:kong /usr/local/share/lua/5.1/kong/plugins/unkey-auth

USER kong
