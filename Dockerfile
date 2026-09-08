# Grafana "sin estado" para el tablero de Abastecimiento 2026.
# Dashboard + datasource horneados por provisioning; no necesita disco
# persistente -> corre en la capa gratis de Render / Hugging Face Spaces / Koyeb.
#
# La base que lo alimenta es sql/02_data_public.sql (SIN nombres de personas).
# Ver README-PUBLICAR.md.
FROM grafana/grafana-oss:11.2.0

# Panel ECharts (Volkov Labs, firmado) horneado en la imagen -> no depende de red
# en el arranque. Version PINNEADA a 6.6.0: es la ultima que soporta Grafana 11
# (grafanaDependency >=10.0.0). Las 7.x piden Grafana >=12.3 y no cargarian aca.
USER root
RUN grafana cli plugins install volkovlabs-echarts-panel 6.6.0
USER grafana

COPY provisioning /etc/grafana/provisioning

# Acceso publico de SOLO LECTURA + endurecimiento
ENV GF_AUTH_ANONYMOUS_ENABLED=true \
    GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer \
    GF_AUTH_ANONYMOUS_ORG_NAME="Main Org." \
    GF_USERS_ALLOW_SIGN_UP=false \
    GF_USERS_VIEWERS_CAN_EDIT=false \
    GF_USERS_DEFAULT_THEME=light \
    GF_EXPLORE_ENABLED=false \
    GF_ALERTING_ENABLED=false \
    GF_SNAPSHOTS_EXTERNAL_ENABLED=false \
    GF_ANALYTICS_REPORTING_ENABLED=false \
    GF_ANALYTICS_CHECK_FOR_UPDATES=false \
    GF_SECURITY_DISABLE_GRAVATAR=true \
    GF_SECURITY_COOKIE_SECURE=true \
    GF_NEWS_NEWS_FEED_ENABLED=false \
    GF_SERVER_HTTP_PORT=3000

# En runtime, pasar como env/secrets del proveedor:
#   GF_SECURITY_ADMIN_PASSWORD   clave admin real (NO la dejes por defecto)
#   GF_SERVER_ROOT_URL           https://<tu-app>.onrender.com
#   GF_SERVER_HTTP_PORT          10000 en Render, 7860 en HF Spaces
#   PG_HOST PG_PORT PG_DATABASE PG_USER PG_PASSWORD PG_SSLMODE   (Postgres de Neon)
EXPOSE 3000
