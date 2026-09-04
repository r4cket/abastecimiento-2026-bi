-- ============================================================================
--  GESTIÓN DE ABASTECIMIENTO HOSPITALARIO 2026  —  esquema + vistas de KPI
--  Fuente: Analisis_Abastecimiento_2026.xlsx (consolidación validada)
--
--  Cadena:  Planificación (PAC inicial → PAC modificado) → Solicitud → Despacho → Compras
--  Unidades: PABELLON, SERVICIO CLINICO CIRUGIA, SERVICIO GINECOLOGIA, SERVICIO OBSTETRICIA
--            (Compras agrupa Gineco+Obst en 'SERVICIO OBSTETRICIA Y GINECOLOGIA')
--
--  Bases temporales (NO son iguales — ver Notas_Metodologicas del Excel):
--    · PAC inicial/modificado : programación anual Ene-Dic 2026 (y subtotal Ene-Ago)
--    · Solicitado vs Despachado: Ene-Ago 2026 (8 meses)
--    · Compras                 : solicitudes creadas Abr-Ago 2026 (cola ABIERTA/editable,
--                                no el universo histórico completo)
-- ============================================================================

DROP VIEW IF EXISTS
    v_cadena_servicio, v_situacion_items, v_pac_reprogramacion, v_pac_tipo_cambio,
    v_despacho_mensual, v_despacho_servicio, v_despacho_bodega,
    v_compras_estado, v_compras_mensual_estado, v_compras_atribucion,
    v_compras_atribucion_problematicas, v_compras_servicio, v_items_criticos,
    v_demanda_no_planificada, v_items_brecha_despacho, v_items_valor,
    v_items_sobre_solicitud, v_items_plan_no_solicitado,
    v_items_quiebre_recurrente CASCADE;
DROP TABLE IF EXISTS
    pac_item, despacho_mensual, cadena_item, compra, caso_reprogramacion,
    articulo, servicio CASCADE;

-- ---------------------------------------------------------------------------
--  Dimensiones
-- ---------------------------------------------------------------------------
CREATE TABLE servicio (
    nombre  VARCHAR(60) PRIMARY KEY,
    es_agrupador BOOLEAN NOT NULL DEFAULT FALSE   -- TRUE para 'OBSTETRICIA Y GINECOLOGIA' (solo Compras)
);

CREATE TABLE articulo (
    codigo_cgcom  VARCHAR(30) PRIMARY KEY,
    descripcion   VARCHAR(200) NOT NULL,
    um            VARCHAR(10),
    precio_ref    NUMERIC(16,2)                   -- $ de referencia (del PAC inicial); puede ser NULL
);

-- ---------------------------------------------------------------------------
--  Hechos
-- ---------------------------------------------------------------------------

-- PAC inicial vs modificado — grano: servicio × artículo (sin mes; totales)
CREATE TABLE pac_item (
    servicio            VARCHAR(60) NOT NULL REFERENCES servicio(nombre),
    codigo_cgcom        VARCHAR(30) NOT NULL REFERENCES articulo(codigo_cgcom),
    cant_inicial_anual      NUMERIC(16,2) NOT NULL DEFAULT 0,   -- Ene-Dic
    cant_modificado_anual   NUMERIC(16,2) NOT NULL DEFAULT 0,
    cant_inicial_eneago     NUMERIC(16,2) NOT NULL DEFAULT 0,
    cant_modificado_eneago  NUMERIC(16,2) NOT NULL DEFAULT 0,
    en_inicial          BOOLEAN NOT NULL,
    en_modificado       BOOLEAN NOT NULL,
    tipo_cambio         VARCHAR(40) NOT NULL,   -- Sin cambio / Aumentó / Disminuyó / Incorporado... / Eliminado...
    diferencia_anual    NUMERIC(16,2) GENERATED ALWAYS AS (cant_modificado_anual - cant_inicial_anual) STORED,
    variacion_pct       NUMERIC(12,4),         -- NULL si no aplica (incorporado/eliminado)
    PRIMARY KEY (servicio, codigo_cgcom)
);

-- Solicitado vs Despachado — grano: mes × servicio × artículo × bodega
CREATE TABLE despacho_mensual (
    periodo         DATE NOT NULL,             -- 2026-MM-01
    servicio        VARCHAR(60) NOT NULL REFERENCES servicio(nombre),
    codigo_cgcom    VARCHAR(30) NOT NULL REFERENCES articulo(codigo_cgcom),
    bodega          VARCHAR(40) NOT NULL,
    cant_solicitada NUMERIC(16,2) NOT NULL DEFAULT 0,
    cant_despachada NUMERIC(16,2) NOT NULL DEFAULT 0,
    brecha          NUMERIC(16,2) GENERATED ALWAYS AS (cant_solicitada - cant_despachada) STORED,
    PRIMARY KEY (periodo, servicio, codigo_cgcom, bodega)
);

-- Cruce completo de la cadena — grano: servicio × artículo (base Ene-Ago)
CREATE TABLE cadena_item (
    servicio             VARCHAR(60) NOT NULL REFERENCES servicio(nombre),
    codigo_cgcom         VARCHAR(30) NOT NULL REFERENCES articulo(codigo_cgcom),
    pac_inicial_eneago      NUMERIC(16,2) NOT NULL DEFAULT 0,
    pac_modificado_eneago   NUMERIC(16,2) NOT NULL DEFAULT 0,
    cant_solicitada         NUMERIC(16,2) NOT NULL DEFAULT 0,
    cant_despachada          NUMERIC(16,2) NOT NULL DEFAULT 0,
    desv_solicitud_vs_mod    NUMERIC(16,2),
    desv_pct_solicitud_vs_mod NUMERIC(12,4),  -- NULL cuando PAC modificado = 0
    brecha_despacho          NUMERIC(16,2) GENERATED ALWAYS AS (cant_solicitada - cant_despachada) STORED,
    cumplimiento_pct         NUMERIC(12,4),   -- NULL cuando solicitada = 0
    en_algun_pac         BOOLEAN NOT NULL,
    fue_solicitado       BOOLEAN NOT NULL,
    situacion            VARCHAR(80) NOT NULL,
    PRIMARY KEY (servicio, codigo_cgcom)
);

-- Compras — grano: solicitud de compra (transaccional)
CREATE TABLE compra (
    n_solicitud           VARCHAR(30) PRIMARY KEY,
    servicio              VARCHAR(60) NOT NULL REFERENCES servicio(nombre),
    tipo_compra           VARCHAR(20),
    solicitante           VARCHAR(80),          -- dato interno; tablero LOCAL
    fecha_creacion        TIMESTAMP NOT NULL,
    periodo               DATE NOT NULL,        -- primer día del mes de creación
    estado_original       VARCHAR(80) NOT NULL,
    estado_categoria      VARCHAR(40) NOT NULL, -- Compra Iniciada / En proceso (derivada) / Pendiente de aprobación / Devuelta / Anulada / Rechazada
    actor_estado          VARCHAR(40),
    atribucion            VARCHAR(80),
    ejecutivo_asignado    VARCHAR(80),
    fecha_asignacion      TIMESTAMP,
    dias_hasta_asignacion NUMERIC(10,2),        -- NULL si no calculable (39/91)
    monto_original        VARCHAR(40),
    monto_limpio          NUMERIC(18,2) NOT NULL DEFAULT 0,
    monto_confiable       BOOLEAN NOT NULL DEFAULT FALSE,
    cerrada               BOOLEAN NOT NULL DEFAULT FALSE,
    archivo_origen        VARCHAR(60),
    es_problematica       BOOLEAN GENERATED ALWAYS AS
                          (estado_categoria IN ('Anulada','Devuelta','Rechazada')) STORED
);

-- Casos de doble cambio significativo Inicial→Modificado→Solicitud
CREATE TABLE caso_reprogramacion (
    servicio           VARCHAR(60) NOT NULL REFERENCES servicio(nombre),
    codigo_cgcom       VARCHAR(30) NOT NULL,
    descripcion        VARCHAR(200) NOT NULL,
    pac_inicial_eneago     NUMERIC(16,2),
    pac_modificado_eneago  NUMERIC(16,2),
    cant_solicitada        NUMERIC(16,2),
    var_pct_ini_mod        NUMERIC(12,4),
    var_pct_mod_sol        NUMERIC(12,4),
    PRIMARY KEY (servicio, codigo_cgcom)
);

CREATE INDEX ix_despacho_periodo ON despacho_mensual (periodo);
CREATE INDEX ix_compra_periodo   ON compra (periodo);

-- ===========================================================================
--  VISTAS DE KPI  (las consulta Grafana; filtran por $servicio / $mes en el panel)
-- ===========================================================================

-- 1) Cadena de abastecimiento por servicio (base Ene-Ago).  = Cruce_Resumen_Servicio
CREATE VIEW v_cadena_servicio AS
SELECT servicio,
       SUM(pac_inicial_eneago)     AS pac_inicial,
       SUM(pac_modificado_eneago)  AS pac_modificado,
       SUM(cant_solicitada)        AS solicitado,
       SUM(cant_despachada)        AS despachado,
       ROUND(SUM(pac_modificado_eneago) / NULLIF(SUM(pac_inicial_eneago),0) - 1, 4)  AS reprogramacion_pct,
       ROUND(SUM(cant_solicitada)  / NULLIF(SUM(pac_modificado_eneago),0) - 1, 4)    AS solicitado_vs_modificado_pct,
       ROUND(SUM(cant_despachada)  / NULLIF(SUM(cant_solicitada),0), 4)              AS cumplimiento_despacho_pct
FROM cadena_item
GROUP BY servicio;

-- 2) Situación de los ítems de la cadena (planificado/solicitado/no planificado…)
CREATE VIEW v_situacion_items AS
SELECT servicio, situacion,
       COUNT(*)                AS n_items,
       SUM(cant_solicitada)    AS solicitado,
       SUM(pac_modificado_eneago) AS pac_modificado
FROM cadena_item
GROUP BY servicio, situacion;

-- 3) Reprogramación del PAC por servicio (base anual Ene-Dic).  = PAC_Resumen_Servicio
CREATE VIEW v_pac_reprogramacion AS
SELECT servicio,
       COUNT(*) FILTER (WHERE en_inicial)                                     AS n_items_inicial,
       COUNT(*) FILTER (WHERE en_modificado)                                  AS n_items_modificado,
       COUNT(*) FILTER (WHERE tipo_cambio LIKE 'Incorporado%')               AS n_incorporados,
       COUNT(*) FILTER (WHERE tipo_cambio LIKE 'Eliminado%')                 AS n_eliminados,
       COUNT(*) FILTER (WHERE tipo_cambio = 'Aumentó')                       AS n_aumentaron,
       COUNT(*) FILTER (WHERE tipo_cambio = 'Disminuyó')                     AS n_disminuyeron,
       COUNT(*) FILTER (WHERE tipo_cambio = 'Sin cambio')                    AS n_sin_cambio,
       SUM(cant_inicial_anual)                                               AS cant_inicial,
       SUM(cant_modificado_anual)                                            AS cant_modificado,
       SUM(cant_modificado_anual) - SUM(cant_inicial_anual)                  AS diferencia_neta,
       ROUND(SUM(cant_modificado_anual) / NULLIF(SUM(cant_inicial_anual),0) - 1, 4) AS variacion_neta_pct,
       ROUND(
         COUNT(*) FILTER (WHERE tipo_cambio <> 'Sin cambio')::numeric
         / NULLIF(COUNT(*) FILTER (WHERE en_inicial OR en_modificado),0), 4)         AS pct_items_modificados
FROM pac_item
GROUP BY servicio;

-- 4) PAC — desglose de tipo de cambio (para barra apilada por servicio)
CREATE VIEW v_pac_tipo_cambio AS
SELECT servicio, tipo_cambio, COUNT(*) AS n_items,
       SUM(ABS(diferencia_anual)) AS movimiento_abs
FROM pac_item
GROUP BY servicio, tipo_cambio;

-- 5) Solicitado vs Despachado por mes.  = Solicitud_Despacho_Resumen (por mes)
CREATE VIEW v_despacho_mensual AS
SELECT periodo, servicio,
       COUNT(*)                 AS n_lineas,
       SUM(cant_solicitada)     AS solicitado,
       SUM(cant_despachada)     AS despachado,
       SUM(cant_solicitada) - SUM(cant_despachada)                         AS brecha,
       ROUND(SUM(cant_despachada) / NULLIF(SUM(cant_solicitada),0), 4)     AS cumplimiento_pct
FROM despacho_mensual
GROUP BY periodo, servicio;

-- 6) Solicitado vs Despachado por servicio (Ene-Ago).  = Solicitud_Despacho_Resumen (por servicio)
CREATE VIEW v_despacho_servicio AS
SELECT servicio,
       COUNT(*)                                        AS n_lineas,
       COUNT(*) FILTER (WHERE brecha > 0)              AS n_lineas_con_brecha,
       SUM(cant_solicitada)                            AS solicitado,
       SUM(cant_despachada)                            AS despachado,
       ROUND(SUM(cant_despachada) / NULLIF(SUM(cant_solicitada),0), 4)    AS cumplimiento_pct,
       ROUND(COUNT(*) FILTER (WHERE brecha > 0)::numeric / NULLIF(COUNT(*),0), 4) AS pct_lineas_con_brecha
FROM despacho_mensual
GROUP BY servicio;

-- 7) Despacho por bodega y mes (Farmacia vs Economato)
CREATE VIEW v_despacho_bodega AS
SELECT periodo, servicio, bodega,
       SUM(cant_solicitada) AS solicitado,
       SUM(cant_despachada) AS despachado,
       ROUND(SUM(cant_despachada) / NULLIF(SUM(cant_solicitada),0), 4) AS cumplimiento_pct
FROM despacho_mensual
GROUP BY periodo, servicio, bodega;

-- 8) Compras por estado.  = Compras_Resumen_Estado
CREATE VIEW v_compras_estado AS
SELECT estado_categoria,
       COUNT(*)                                                          AS n_solicitudes,
       ROUND(COUNT(*)::numeric / NULLIF(SUM(COUNT(*)) OVER (),0), 4)     AS pct_del_total,
       SUM(monto_limpio) FILTER (WHERE monto_confiable)                  AS monto_total_confiable,
       ROUND(AVG(monto_limpio) FILTER (WHERE monto_confiable), 0)        AS monto_promedio,
       COUNT(*) FILTER (WHERE dias_hasta_asignacion IS NOT NULL)         AS n_dias_calculables,
       ROUND(AVG(dias_hasta_asignacion), 1)                              AS dias_prom_asignacion
FROM compra
GROUP BY estado_categoria;

-- 9) Compras — evolución mensual por estado.  = Compras_Resumen_Estado (evolución)
CREATE VIEW v_compras_mensual_estado AS
SELECT periodo, estado_categoria, COUNT(*) AS n_solicitudes
FROM compra
GROUP BY periodo, estado_categoria;

-- 10) Compras — atribución de causas (sobre las 91).  = Compras_Atribucion
CREATE VIEW v_compras_atribucion AS
SELECT atribucion,
       COUNT(*)                                                       AS n_solicitudes,
       ROUND(COUNT(*)::numeric / NULLIF(SUM(COUNT(*)) OVER (),0), 4)  AS pct_del_total
FROM compra
WHERE atribucion IS NOT NULL
GROUP BY atribucion;

-- 11) Compras — atribución solo de las problemáticas (Anulada/Devuelta/Rechazada)
CREATE VIEW v_compras_atribucion_problematicas AS
SELECT atribucion,
       COUNT(*)                                                       AS n_solicitudes,
       ROUND(COUNT(*)::numeric / NULLIF(SUM(COUNT(*)) OVER (),0), 4)  AS pct_de_problematicas
FROM compra
WHERE es_problematica AND atribucion IS NOT NULL
GROUP BY atribucion;

-- 12) Compras por servicio (base muestral pequeña — Cirugía solo 2)
CREATE VIEW v_compras_servicio AS
SELECT servicio,
       COUNT(*)                                    AS n_solicitudes,
       COUNT(*) FILTER (WHERE es_problematica)     AS n_problematicas,
       ROUND(COUNT(*) FILTER (WHERE es_problematica)::numeric / NULLIF(COUNT(*),0), 4) AS pct_problematicas,
       SUM(monto_limpio) FILTER (WHERE monto_confiable) AS monto_total_confiable
FROM compra
GROUP BY servicio;

-- 13) Ítems críticos — doble cambio Inicial→Modificado→Solicitud
CREATE VIEW v_items_criticos AS
SELECT servicio, codigo_cgcom, descripcion,
       pac_inicial_eneago, pac_modificado_eneago, cant_solicitada,
       var_pct_ini_mod, var_pct_mod_sol,
       ABS(var_pct_ini_mod) + ABS(var_pct_mod_sol) AS magnitud_cambio
FROM caso_reprogramacion;

-- 14) Demanda no planificada — solicitado sin estar en ningún PAC
CREATE VIEW v_demanda_no_planificada AS
SELECT ci.servicio, ci.codigo_cgcom, a.descripcion, a.um,
       ci.cant_solicitada, ci.cant_despachada, ci.cumplimiento_pct
FROM cadena_item ci
JOIN articulo a ON a.codigo_cgcom = ci.codigo_cgcom
WHERE ci.situacion = 'Solicitado sin estar en PAC (demanda no planificada)';

-- 15) Ítems con mayor brecha de despacho (demanda no satisfecha, en unidades)
CREATE VIEW v_items_brecha_despacho AS
SELECT ci.servicio, ci.codigo_cgcom, a.descripcion, a.um,
       ci.cant_solicitada, ci.cant_despachada, ci.brecha_despacho, ci.cumplimiento_pct,
       ROUND(COALESCE(a.precio_ref,0) * ci.brecha_despacho, 0) AS valor_brecha_estimado
FROM cadena_item ci
JOIN articulo a ON a.codigo_cgcom = ci.codigo_cgcom
WHERE ci.brecha_despacho > 0;

-- 16) Ítems de mayor valor económico (precio ref x cantidad, base Ene-Ago)
CREATE VIEW v_items_valor AS
SELECT ci.servicio, ci.codigo_cgcom, a.descripcion, a.um, a.precio_ref,
       ci.pac_modificado_eneago, ci.cant_solicitada, ci.cant_despachada,
       ROUND(COALESCE(a.precio_ref,0) * ci.pac_modificado_eneago, 0) AS valor_pac_modificado,
       ROUND(COALESCE(a.precio_ref,0) * ci.cant_solicitada, 0)       AS valor_solicitado,
       ROUND(COALESCE(a.precio_ref,0) * ci.cant_despachada, 0)       AS valor_despachado
FROM cadena_item ci
JOIN articulo a ON a.codigo_cgcom = ci.codigo_cgcom
WHERE COALESCE(a.precio_ref,0) > 0;

-- 17) Ítems solicitados muy por encima del PAC modificado (>=30%, con volumen)
CREATE VIEW v_items_sobre_solicitud AS
SELECT ci.servicio, ci.codigo_cgcom, a.descripcion, a.um,
       ci.pac_modificado_eneago, ci.cant_solicitada,
       ci.desv_solicitud_vs_mod, ci.desv_pct_solicitud_vs_mod, ci.cumplimiento_pct
FROM cadena_item ci
JOIN articulo a ON a.codigo_cgcom = ci.codigo_cgcom
WHERE ci.pac_modificado_eneago >= 50
  AND ci.desv_pct_solicitud_vs_mod IS NOT NULL
  AND ci.desv_pct_solicitud_vs_mod >= 0.30;

-- 18) Ítems planificados (Ene-Ago) pero nunca solicitados -> sobre-planificación
CREATE VIEW v_items_plan_no_solicitado AS
SELECT ci.servicio, ci.codigo_cgcom, a.descripcion, a.um,
       ci.pac_inicial_eneago, ci.pac_modificado_eneago,
       ROUND(COALESCE(a.precio_ref,0) * ci.pac_modificado_eneago, 0) AS valor_pac_modificado
FROM cadena_item ci
JOIN articulo a ON a.codigo_cgcom = ci.codigo_cgcom
WHERE ci.situacion = 'Planificado Ene-Ago pero nunca solicitado';

-- 19) Quiebre de stock recurrente: brecha de despacho en 3+ meses distintos
CREATE VIEW v_items_quiebre_recurrente AS
SELECT dm.servicio, dm.codigo_cgcom, a.descripcion, a.um,
       COUNT(DISTINCT dm.periodo) FILTER (WHERE dm.brecha > 0) AS meses_con_brecha,
       COUNT(DISTINCT dm.periodo)                              AS meses_con_movimiento,
       SUM(dm.cant_solicitada)                                 AS solicitado_total,
       SUM(dm.cant_despachada)                                 AS despachado_total,
       SUM(dm.brecha) FILTER (WHERE dm.brecha > 0)             AS brecha_acumulada,
       ROUND(SUM(dm.cant_despachada) / NULLIF(SUM(dm.cant_solicitada),0), 4) AS cumplimiento_pct
FROM despacho_mensual dm
JOIN articulo a ON a.codigo_cgcom = dm.codigo_cgcom
GROUP BY dm.servicio, dm.codigo_cgcom, a.descripcion, a.um
HAVING COUNT(DISTINCT dm.periodo) FILTER (WHERE dm.brecha > 0) >= 3;
