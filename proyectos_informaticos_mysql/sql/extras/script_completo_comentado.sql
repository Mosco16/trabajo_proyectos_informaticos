-- =============================================================================================================
-- MYSQL SCRIPT - SISTEMA DE GESTIÓN DE PROYECTOS INFORMÁTICOS
-- =============================================================================================================
-- Sintaxis: MySQL
-- Encoding: UTF-8
-- Autor: [Daniel Hincapié]
-- Fecha: 15 de Septiembre de 2025
-- Descripción: Script consolidado que contiene toda la lógica de la base de datos para gestión de 
--              proyectos informáticos, incluyendo creación de tablas, procedimientos almacenados, 
--              triggers, funciones y datos de prueba.
-- Propósito Académico: Evidencia de análisis explicativo detallado del script SQL para clase de BD
-- =============================================================================================================

-- =============================================================================================================
-- SECCIÓN 1: CREACIÓN Y SELECCIÓN DE LA BASE DE DATOS
-- =============================================================================================================

-- Instrucción para crear la base de datos si no existe
-- IF NOT EXISTS evita errores si la base ya está creada
CREATE DATABASE IF NOT EXISTS proyectos_informaticos;

-- Selecciona la base de datos recién creada para trabajar en ella
-- Todas las instrucciones siguientes se ejecutarán en este contexto
USE proyectos_informaticos;

-- =============================================================================================================
-- SECCIÓN 2: LIMPIEZA Y PREPARACIÓN DEL ENTORNO
-- =============================================================================================================

-- ELIMINACIÓN DE TRIGGERS EXISTENTES
-- Los triggers se eliminan primero para evitar conflictos durante la recreación de tablas
DROP TRIGGER IF EXISTS tr_docente_after_update;  -- Trigger que se ejecuta después de actualizar un docente
DROP TRIGGER IF EXISTS tr_docente_after_delete;  -- Trigger que se ejecuta después de eliminar un docente

-- ELIMINACIÓN DE TABLAS EXISTENTES EN ORDEN CORRECTO
-- Se respeta el orden debido a las claves foráneas (dependencias)
DROP TABLE IF EXISTS copia_eliminados_docente;    -- Tabla de auditoría para docentes eliminados
DROP TABLE IF EXISTS copia_actualizados_docente;  -- Tabla de auditoría para docentes actualizados
DROP TABLE IF EXISTS proyecto;                    -- Tabla hija (tiene FK hacia docente)
DROP TABLE IF EXISTS docente;                     -- Tabla padre (es referenciada por proyecto)

-- =============================================================================================================
-- SECCIÓN 3: CREACIÓN DE TABLAS PRINCIPALES
-- =============================================================================================================

-- TABLA DOCENTE
-- Almacena información de los docentes que pueden liderar proyectos
CREATE TABLE docente (
  -- Clave primaria autoincremental
  docente_id        INT AUTO_INCREMENT PRIMARY KEY,
  
  -- Número de documento único (cédula, pasaporte, etc.)
  numero_documento  VARCHAR(20)  NOT NULL,
  
  -- Nombres completos del docente
  nombres           VARCHAR(120) NOT NULL,
  
  -- Título académico (opcional - puede ser NULL)
  titulo            VARCHAR(120),
  
  -- Años de experiencia profesional (por defecto 0, no puede ser negativo)
  anios_experiencia INT          NOT NULL DEFAULT 0,
  
  -- Dirección de residencia (opcional)
  direccion         VARCHAR(180),
  
  -- Tipo de vinculación (Tiempo completo, Cátedra, etc.)
  tipo_docente      VARCHAR(40),
  
  -- RESTRICCIONES DE INTEGRIDAD
  -- Garantiza que no haya dos docentes con el mismo documento
  CONSTRAINT uq_docente_documento UNIQUE (numero_documento),
  
  -- Garantiza que los años de experiencia no sean negativos
  CONSTRAINT ck_docente_anios CHECK (anios_experiencia >= 0)
  
-- Motor de almacenamiento InnoDB para soporte de transacciones y claves foráneas
) ENGINE=InnoDB;

-- TABLA PROYECTO
-- Almacena información de los proyectos informáticos
CREATE TABLE proyecto (
  -- Clave primaria autoincremental
  proyecto_id      INT AUTO_INCREMENT PRIMARY KEY,
  
  -- Nombre del proyecto (obligatorio)
  nombre           VARCHAR(120) NOT NULL,
  
  -- Descripción detallada del proyecto (opcional)
  descripcion      VARCHAR(400),
  
  -- Fecha de inicio del proyecto (obligatoria)
  fecha_inicial    DATE NOT NULL,
  
  -- Fecha de finalización (opcional - puede ser NULL si está en curso)
  fecha_final      DATE,
  
  -- Presupuesto asignado en pesos colombianos (por defecto 0, no negativo)
  presupuesto      DECIMAL(12,2) NOT NULL DEFAULT 0,
  
  -- Horas estimadas/reales del proyecto (por defecto 0, no negativo)
  horas            INT           NOT NULL DEFAULT 0,
  
  -- Clave foránea hacia la tabla docente (docente líder del proyecto)
  docente_id_jefe  INT NOT NULL,
  
  -- RESTRICCIONES DE INTEGRIDAD
  -- Las horas no pueden ser negativas
  CONSTRAINT ck_proyecto_horas CHECK (horas >= 0),
  
  -- El presupuesto no puede ser negativo
  CONSTRAINT ck_proyecto_pres CHECK (presupuesto >= 0),
  
  -- La fecha final debe ser posterior o igual a la inicial (si existe)
  CONSTRAINT ck_proyecto_fechas CHECK (fecha_final IS NULL OR fecha_final >= fecha_inicial),
  
  -- Clave foránea que referencia al docente líder
  -- ON UPDATE CASCADE: si cambia el ID del docente, se actualiza automáticamente aquí
  -- ON DELETE RESTRICT: no permite eliminar un docente que tenga proyectos asignados
  CONSTRAINT fk_proyecto_docente FOREIGN KEY (docente_id_jefe) REFERENCES docente(docente_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- =============================================================================================================
-- SECCIÓN 4: TABLAS DE AUDITORÍA
-- =============================================================================================================

-- TABLA PARA AUDITAR ACTUALIZACIONES DE DOCENTES
-- Registra todas las modificaciones realizadas a los docentes
CREATE TABLE copia_actualizados_docente (
  -- Clave primaria de la auditoría
  auditoria_id       INT AUTO_INCREMENT PRIMARY KEY,
  
  -- Copia de todos los campos del docente actualizado
  docente_id         INT NOT NULL,
  numero_documento   VARCHAR(20)  NOT NULL,
  nombres            VARCHAR(120) NOT NULL,
  titulo             VARCHAR(120),
  anios_experiencia  INT          NOT NULL,
  direccion          VARCHAR(180),
  tipo_docente       VARCHAR(40),
  
  -- Información de auditoría automática
  -- Fecha y hora exacta de la modificación (UTC)
  accion_fecha       DATETIME     NOT NULL DEFAULT (UTC_TIMESTAMP()),
  
  -- Usuario de MySQL que realizó la modificación
  usuario_sql        VARCHAR(128) NOT NULL DEFAULT (CURRENT_USER())
) ENGINE=InnoDB;

-- TABLA PARA AUDITAR ELIMINACIONES DE DOCENTES
-- Registra todos los docentes que han sido eliminados del sistema
CREATE TABLE copia_eliminados_docente (
  -- Clave primaria de la auditoría
  auditoria_id       INT AUTO_INCREMENT PRIMARY KEY,
  
  -- Copia de todos los campos del docente eliminado
  docente_id         INT NOT NULL,
  numero_documento   VARCHAR(20)  NOT NULL,
  nombres            VARCHAR(120) NOT NULL,
  titulo             VARCHAR(120),
  anios_experiencia  INT          NOT NULL,
  direccion          VARCHAR(180),
  tipo_docente       VARCHAR(40),
  
  -- Información de auditoría automática
  accion_fecha       DATETIME     NOT NULL DEFAULT (UTC_TIMESTAMP()),
  usuario_sql        VARCHAR(128) NOT NULL DEFAULT (CURRENT_USER())
) ENGINE=InnoDB;

-- =============================================================================================================
-- SECCIÓN 5: PROCEDIMIENTOS ALMACENADOS PARA DOCENTES (CRUD)
-- =============================================================================================================

-- ELIMINACIÓN DE PROCEDIMIENTOS EXISTENTES
-- Se eliminan antes de crearlos para evitar conflictos
DROP PROCEDURE IF EXISTS sp_docente_crear;
DROP PROCEDURE IF EXISTS sp_docente_leer;
DROP PROCEDURE IF EXISTS sp_docente_actualizar;
DROP PROCEDURE IF EXISTS sp_docente_eliminar;

-- Cambio del delimitador para poder usar ; dentro de los procedimientos
DELIMITER $$

-- PROCEDIMIENTO PARA CREAR UN DOCENTE
-- Inserta un nuevo registro en la tabla docente
CREATE PROCEDURE sp_docente_crear(
  IN p_numero_documento VARCHAR(20),   -- Parámetro de entrada: documento del docente
  IN p_nombres          VARCHAR(120),  -- Parámetro de entrada: nombres del docente
  IN p_titulo           VARCHAR(120),  -- Parámetro de entrada: título académico
  IN p_anios_experiencia INT,          -- Parámetro de entrada: años de experiencia
  IN p_direccion        VARCHAR(180),  -- Parámetro de entrada: dirección
  IN p_tipo_docente     VARCHAR(40)    -- Parámetro de entrada: tipo de docente
)
BEGIN
  -- Inserción del nuevo docente con validación de años de experiencia
  -- IFNULL garantiza que si se pasa NULL, se asigne 0
  INSERT INTO docente (numero_documento, nombres, titulo, anios_experiencia, direccion, tipo_docente)
  VALUES (p_numero_documento, p_nombres, p_titulo, IFNULL(p_anios_experiencia,0), p_direccion, p_tipo_docente);
  
  -- Retorna el ID del docente recién creado
  SELECT LAST_INSERT_ID() AS docente_id_creado;
END$$

-- PROCEDIMIENTO PARA LEER/CONSULTAR UN DOCENTE
-- Obtiene todos los datos de un docente específico
CREATE PROCEDURE sp_docente_leer(IN p_docente_id INT)
BEGIN
  -- Selecciona todos los campos del docente con el ID especificado
  SELECT * FROM docente WHERE docente_id = p_docente_id;
END$$

-- PROCEDIMIENTO PARA ACTUALIZAR UN DOCENTE
-- Modifica los datos de un docente existente
CREATE PROCEDURE sp_docente_actualizar(
  IN p_docente_id       INT,
  IN p_numero_documento VARCHAR(20),
  IN p_nombres          VARCHAR(120),
  IN p_titulo           VARCHAR(120),
  IN p_anios_experiencia INT,
  IN p_direccion        VARCHAR(180),
  IN p_tipo_docente     VARCHAR(40)
)
BEGIN
  -- Actualización de todos los campos del docente
  UPDATE docente
     SET numero_documento = p_numero_documento,
         nombres = p_nombres,
         titulo = p_titulo,
         anios_experiencia = IFNULL(p_anios_experiencia,0),  -- Validación NULL
         direccion = p_direccion,
         tipo_docente = p_tipo_docente
   WHERE docente_id = p_docente_id;
   
  -- Retorna el registro actualizado para confirmación
  SELECT * FROM docente WHERE docente_id = p_docente_id;
END$$

-- PROCEDIMIENTO PARA ELIMINAR UN DOCENTE
-- Elimina un docente del sistema (si no tiene proyectos asociados)
CREATE PROCEDURE sp_docente_eliminar(IN p_docente_id INT)
BEGIN
  -- Eliminación del docente
  -- Si tiene proyectos asociados, fallará por la restricción FOREIGN KEY
  DELETE FROM docente WHERE docente_id = p_docente_id;
END$$

-- =============================================================================================================
-- SECCIÓN 6: PROCEDIMIENTOS ALMACENADOS PARA PROYECTOS (CRUD)
-- =============================================================================================================

-- ELIMINACIÓN DE PROCEDIMIENTOS EXISTENTES
DROP PROCEDURE IF EXISTS sp_proyecto_crear;
DROP PROCEDURE IF EXISTS sp_proyecto_leer;
DROP PROCEDURE IF EXISTS sp_proyecto_actualizar;
DROP PROCEDURE IF EXISTS sp_proyecto_eliminar;

-- PROCEDIMIENTO PARA CREAR UN PROYECTO
CREATE PROCEDURE sp_proyecto_crear(
  IN p_nombre           VARCHAR(120),   -- Nombre del proyecto
  IN p_descripcion      VARCHAR(400),   -- Descripción del proyecto
  IN p_fecha_inicial    DATE,           -- Fecha de inicio
  IN p_fecha_final      DATE,           -- Fecha de finalización (puede ser NULL)
  IN p_presupuesto      DECIMAL(12,2),  -- Presupuesto del proyecto
  IN p_horas            INT,            -- Horas estimadas
  IN p_docente_id_jefe  INT             -- ID del docente líder
)
BEGIN
  -- Inserción del nuevo proyecto con validaciones
  INSERT INTO proyecto (nombre, descripcion, fecha_inicial, fecha_final, presupuesto, horas, docente_id_jefe)
  VALUES (p_nombre, p_descripcion, p_fecha_inicial, p_fecha_final, 
          IFNULL(p_presupuesto,0), IFNULL(p_horas,0), p_docente_id_jefe);
  
  -- Retorna el ID del proyecto recién creado
  SELECT LAST_INSERT_ID() AS proyecto_id_creado;
END$$

-- PROCEDIMIENTO PARA LEER UN PROYECTO CON INFORMACIÓN DEL DOCENTE
-- Obtiene datos del proyecto junto con el nombre del docente líder
CREATE PROCEDURE sp_proyecto_leer(IN p_proyecto_id INT)
BEGIN
  -- JOIN para obtener información completa del proyecto y su líder
  SELECT p.*, d.nombres AS nombre_docente_jefe
  FROM proyecto p
  JOIN docente d ON d.docente_id = p.docente_id_jefe
  WHERE p.proyecto_id = p_proyecto_id;
END$$

-- PROCEDIMIENTO PARA ACTUALIZAR UN PROYECTO
CREATE PROCEDURE sp_proyecto_actualizar(
  IN p_proyecto_id      INT,
  IN p_nombre           VARCHAR(120),
  IN p_descripcion      VARCHAR(400),
  IN p_fecha_inicial    DATE,
  IN p_fecha_final      DATE,
  IN p_presupuesto      DECIMAL(12,2),
  IN p_horas            INT,
  IN p_docente_id_jefe  INT
)
BEGIN
  -- Actualización de todos los campos del proyecto
  UPDATE proyecto
     SET nombre = p_nombre,
         descripcion = p_descripcion,
         fecha_inicial = p_fecha_inicial,
         fecha_final = p_fecha_final,
         presupuesto = IFNULL(p_presupuesto,0),
         horas = IFNULL(p_horas,0),
         docente_id_jefe = p_docente_id_jefe
   WHERE proyecto_id = p_proyecto_id;
   
  -- Llama al procedimiento de lectura para mostrar el proyecto actualizado
  CALL sp_proyecto_leer(p_proyecto_id);
END$$

-- PROCEDIMIENTO PARA ELIMINAR UN PROYECTO
CREATE PROCEDURE sp_proyecto_eliminar(IN p_proyecto_id INT)
BEGIN
  -- Eliminación del proyecto especificado
  DELETE FROM proyecto WHERE proyecto_id = p_proyecto_id;
END$$

-- =============================================================================================================
-- SECCIÓN 7: FUNCIÓN DEFINIDA POR EL USUARIO (UDF)
-- =============================================================================================================

-- ELIMINACIÓN DE FUNCIÓN EXISTENTE
DROP FUNCTION IF EXISTS fn_promedio_presupuesto_por_docente;

-- FUNCIÓN PARA CALCULAR EL PROMEDIO DE PRESUPUESTO POR DOCENTE
-- Calcula el promedio de presupuestos de todos los proyectos liderados por un docente
CREATE FUNCTION fn_promedio_presupuesto_por_docente(p_docente_id INT)
RETURNS DECIMAL(12,2)      -- Tipo de dato que retorna
DETERMINISTIC              -- El resultado es siempre el mismo para los mismos parámetros
READS SQL DATA             -- La función lee datos de la base de datos
BEGIN
  DECLARE v_prom DECIMAL(12,2);  -- Variable local para almacenar el promedio
  
  -- Calcula el promedio de presupuestos para el docente especificado
  -- IFNULL maneja el caso donde no hay proyectos (evita NULL)
  SELECT IFNULL(AVG(presupuesto),0) INTO v_prom
  FROM proyecto
  WHERE docente_id_jefe = p_docente_id;
  
  -- Retorna el promedio calculado (0 si no hay proyectos)
  RETURN IFNULL(v_prom,0);
END$$

-- =============================================================================================================
-- SECCIÓN 8: TRIGGERS PARA AUDITORÍA AUTOMÁTICA
-- =============================================================================================================

-- TRIGGER PARA AUDITAR ACTUALIZACIONES DE DOCENTES
-- Se ejecuta automáticamente DESPUÉS de cada UPDATE en la tabla docente
CREATE TRIGGER tr_docente_after_update
AFTER UPDATE ON docente    -- Se ejecuta después de actualizar un registro
FOR EACH ROW               -- Se ejecuta para cada fila afectada
BEGIN
  -- Inserta una copia del registro actualizado en la tabla de auditoría
  -- NEW contiene los valores nuevos después de la actualización
  INSERT INTO copia_actualizados_docente
    (docente_id, numero_documento, nombres, titulo, anios_experiencia, direccion, tipo_docente)
  VALUES
    (NEW.docente_id, NEW.numero_documento, NEW.nombres, NEW.titulo, 
     NEW.anios_experiencia, NEW.direccion, NEW.tipo_docente);
END$$

-- TRIGGER PARA AUDITAR ELIMINACIONES DE DOCENTES
-- Se ejecuta automáticamente DESPUÉS de cada DELETE en la tabla docente
CREATE TRIGGER tr_docente_after_delete
AFTER DELETE ON docente    -- Se ejecuta después de eliminar un registro
FOR EACH ROW               -- Se ejecuta para cada fila eliminada
BEGIN
  -- Inserta una copia del registro eliminado en la tabla de auditoría
  -- OLD contiene los valores antes de la eliminación
  INSERT INTO copia_eliminados_docente
    (docente_id, numero_documento, nombres, titulo, anios_experiencia, direccion, tipo_docente)
  VALUES
    (OLD.docente_id, OLD.numero_documento, OLD.nombres, OLD.titulo, 
     OLD.anios_experiencia, OLD.direccion, OLD.tipo_docente);
END$$

-- Restaurar el delimitador por defecto
DELIMITER ;

-- =============================================================================================================
-- SECCIÓN 9: ÍNDICES PARA OPTIMIZACIÓN DE CONSULTAS
-- =============================================================================================================

-- ÍNDICE EN LA CLAVE FORÁNEA
-- Mejora el rendimiento de JOINs entre proyecto y docente
CREATE INDEX ix_proyecto_docente ON proyecto(docente_id_jefe);

-- ÍNDICE EN EL NÚMERO DE DOCUMENTO
-- Mejora el rendimiento de búsquedas por documento (campo único frecuentemente consultado)
CREATE INDEX ix_docente_documento ON docente(numero_documento);

-- =============================================================================================================
-- SECCIÓN 10: INSERCIÓN DE DATOS INICIALES (SEED DATA)
-- =============================================================================================================

-- DOCENTES INICIALES (usando procedimientos almacenados)
-- Docente 1: Ana Gómez - Tiempo completo con experiencia en sistemas
CALL sp_docente_crear('CC1001', 'Ana Gómez', 'MSc. Ing. Sistemas', 6, 'Cra 10 # 5-55', 'Tiempo completo');

-- Docente 2: Carlos Ruiz - Cátedra con experiencia en informática
CALL sp_docente_crear('CC1002', 'Carlos Ruiz', 'Ing. Informático', 3, 'Cll 20 # 4-10', 'Cátedra');

-- OBTENCIÓN DE IDs PARA REFERENCIAR EN PROYECTOS
-- Variables de sesión para almacenar los IDs de los docentes recién creados
SET @id_ana    := (SELECT docente_id FROM docente WHERE numero_documento='CC1001');
SET @id_carlos := (SELECT docente_id FROM docente WHERE numero_documento='CC1002');

-- PROYECTOS INICIALES (usando procedimientos almacenados)
-- Proyecto 1: Plataforma académica liderada por Ana Gómez
CALL sp_proyecto_crear('Plataforma Académica', 'Módulos de matrícula', '2025-01-01', NULL, 25000000, 800, @id_ana);

-- Proyecto 2: Chat de soporte liderado por Carlos Ruiz
CALL sp_proyecto_crear('Chat Soporte TI', 'Chat universitario', '2025-02-01', '2025-06-30', 12000000, 450, @id_carlos);

-- =============================================================================================================
-- SECCIÓN 11: NUEVOS DOCENTES ADICIONALES (6 REGISTROS SOLICITADOS)
-- =============================================================================================================

-- DOCENTE 3: María López - Especialista en gestión de proyectos
-- Profesional con experiencia en metodologías ágiles y gestión
CALL sp_docente_crear('CC2001', 'María López', 'Esp. Gestión de Proyectos', 7, 'Av. Siempre Viva 742', 'Cátedra');

-- DOCENTE 4: Jorge Torres - Magíster en ingeniería de software
-- Experto en desarrollo de software y arquitecturas empresariales
CALL sp_docente_crear('CC3001', 'Jorge Torres', 'MSc. Ing. Software', 8, 'Cra 45 # 12-34', 'Tiempo completo');

-- DOCENTE 5: Laura Medina - Doctora en ciencias computacionales
-- Investigadora senior en inteligencia artificial y machine learning
CALL sp_docente_crear('CC4001', 'Laura Medina', 'PhD. Ciencias Computacionales', 12, 'Cll 78 # 23-45', 'Tiempo completo');

-- DOCENTE 6: Roberto Silva - Especialista en seguridad informática
-- Experto en ciberseguridad y protección de sistemas
CALL sp_docente_crear('CC5001', 'Roberto Silva', 'Esp. Seguridad Informática', 5, 'Av. Las Flores 156', 'Cátedra');

-- DOCENTE 7: Patricia Vargas - Magíster en bases de datos
-- Especialista en diseño y administración de bases de datos
CALL sp_docente_crear('CC6001', 'Patricia Vargas', 'MSc. Bases de Datos', 9, 'Cra 67 # 89-12', 'Tiempo completo');

-- DOCENTE 8: Fernando Castro - Ingeniero en sistemas con MBA
-- Profesional con experiencia en dirección de proyectos tecnológicos
CALL sp_docente_crear('CC7001', 'Fernando Castro', 'Ing. Sistemas, MBA', 10, 'Cll 34 # 56-78', 'Tiempo completo');

-- OBTENCIÓN DE IDs DE LOS NUEVOS DOCENTES
-- Variables para referenciar a los nuevos docentes en los proyectos
SET @id_maria    := (SELECT docente_id FROM docente WHERE numero_documento='CC2001');
SET @id_jorge    := (SELECT docente_id FROM docente WHERE numero_documento='CC3001');
SET @id_laura    := (SELECT docente_id FROM docente WHERE numero_documento='CC4001');
SET @id_roberto  := (SELECT docente_id FROM docente WHERE numero_documento='CC5001');
SET @id_patricia := (SELECT docente_id FROM docente WHERE numero_documento='CC6001');
SET @id_fernando := (SELECT docente_id FROM docente WHERE numero_documento='CC7001');

-- =============================================================================================================
-- SECCIÓN 12: PROYECTOS PARA LOS NUEVOS DOCENTES
-- =============================================================================================================

-- PROYECTO 3: App de biblioteca - María López
-- Aplicación móvil para gestión de préstamos bibliotecarios
CALL sp_proyecto_crear('App Biblioteca', 'App móvil de préstamos', '2025-03-01', NULL, 9000000, 320, @id_maria);

-- PROYECTO 4: Sistema de nómina - Jorge Torres
-- Módulo integral de recursos humanos y nómina
CALL sp_proyecto_crear('Sistema Nómina', 'Módulo RRHH', '2025-04-01', NULL, 15000000, 500, @id_jorge);

-- PROYECTO 5: Plataforma IA Educativa - Laura Medina
-- Sistema de inteligencia artificial para personalización del aprendizaje
CALL sp_proyecto_crear('Plataforma IA Educativa', 'IA para personalización de aprendizaje', '2025-02-15', '2025-12-31', 35000000, 1200, @id_laura);

-- PROYECTO 6: Sistema de Seguridad - Roberto Silva
-- Plataforma integral de monitoreo y seguridad informática
CALL sp_proyecto_crear('Sistema Seguridad Campus', 'Monitoreo y protección de red universitaria', '2025-03-15', '2025-09-30', 18000000, 600, @id_roberto);

-- PROYECTO 7: Data Warehouse Institucional - Patricia Vargas
-- Almacén de datos para análisis institucional y toma de decisiones
CALL sp_proyecto_crear('Data Warehouse Institucional', 'Almacén de datos para análisis y reportes', '2025-01-15', NULL, 28000000, 900, @id_patricia);

-- PROYECTO 8: Portal de Egresados - Fernando Castro
-- Plataforma web para conexión y seguimiento de egresados
CALL sp_proyecto_crear('Portal Egresados', 'Plataforma de conexión y seguimiento', '2025-05-01', '2025-11-30', 12500000, 400, @id_fernando);

-- =============================================================================================================
-- SECCIÓN 13: DEMOSTRACIÓN DE TRIGGERS Y AUDITORÍA
-- =============================================================================================================

-- ACTUALIZACIÓN PARA DEMOSTRAR TRIGGER DE UPDATE
-- Modifica información de Carlos Ruiz para disparar el trigger de auditoría
CALL sp_docente_actualizar(@id_carlos, 'CC1002', 'Carlos A. Ruiz', 'Esp. Base de Datos', 4, 'Cll 20 # 4-10', 'Cátedra');

-- La actualización anterior automáticamente insertó un registro en copia_actualizados_docente
-- debido al trigger tr_docente_after_update

-- EJEMPLO DE ELIMINACIÓN (COMENTADO PARA PRESERVAR DATOS)
-- Eliminar proyectos de Ana primero (requisito para poder eliminar el docente)
-- DELETE FROM proyecto WHERE docente_id_jefe = @id_ana;
-- CALL sp_docente_eliminar(@id_ana);
-- Esta eliminación dispararía el trigger tr_docente_after_delete

-- =============================================================================================================
-- SECCIÓN 14: CONSULTAS DE VERIFICACIÓN Y ANÁLISIS
-- =============================================================================================================

-- CONSULTA 1: Listado de todos los docentes y sus datos
SELECT 'LISTADO COMPLETO DE DOCENTES' AS seccion;
SELECT docente_id, numero_documento, nombres, titulo, anios_experiencia, direccion, tipo_docente
FROM docente
ORDER BY docente_id;

-- CONSULTA 2: Proyectos con información de sus docentes líderes
SELECT 'PROYECTOS Y SUS DOCENTES LÍDERES' AS seccion;
SELECT p.proyecto_id, p.nombre AS proyecto, p.presupuesto, p.horas, d.nombres AS docente_jefe
FROM proyecto p
JOIN docente d ON d.docente_id = p.docente_id_jefe
ORDER BY p.proyecto_id;

-- CONSULTA 3: Promedio de presupuesto por docente usando la UDF
SELECT 'PROMEDIO DE PRESUPUESTO POR DOCENTE (UDF)' AS seccion;
SELECT d.docente_id, d.nombres,
       fn_promedio_presupuesto_por_docente(d.docente_id) AS promedio_presupuesto
FROM docente d
ORDER BY promedio_presupuesto DESC;

-- CONSULTA 4: Verificación de auditoría de actualizaciones
SELECT 'AUDITORÍA DE ACTUALIZACIONES' AS seccion;
SELECT * FROM copia_actualizados_docente
ORDER BY auditoria_id DESC;

-- CONSULTA 5: Verificación de auditoría de eliminaciones
SELECT 'AUDITORÍA DE ELIMINACIONES' AS seccion;
SELECT * FROM copia_eliminados_docente
ORDER BY auditoria_id DESC;

-- CONSULTA 6: Docentes con sus proyectos (incluyendo docentes sin proyectos)
SELECT 'DOCENTES Y SUS PROYECTOS (LEFT JOIN)' AS seccion;
SELECT d.docente_id, d.nombres, 
       COALESCE(p.proyecto_id, 0) AS proyecto_id, 
       COALESCE(p.nombre, 'Sin proyectos asignados') AS proyecto
FROM docente d
LEFT JOIN proyecto p ON d.docente_id = p.docente_id_jefe
ORDER BY d.docente_id, p.proyecto_id;

-- CONSULTA 7: Total de horas y presupuesto por docente
SELECT 'RESUMEN DE HORAS Y PRESUPUESTO POR DOCENTE' AS seccion;
SELECT d.docente_id, d.nombres, 
       COUNT(p.proyecto_id) AS num_proyectos,
       COALESCE(SUM(p.horas), 0) AS total_horas,
       COALESCE(SUM(p.presupuesto), 0) AS total_presupuesto
FROM docente d
LEFT JOIN proyecto p ON d.docente_id = p.docente_id_jefe
GROUP BY d.docente_id, d.nombres
ORDER BY total_presupuesto DESC;

-- CONSULTA 8: Validación de restricciones CHECK
SELECT 'VALIDACIÓN DE RESTRICCIONES' AS seccion;
SELECT proyecto_id, nombre, fecha_inicial, fecha_final, presupuesto, horas,
       CASE 
         WHEN fecha_final IS NULL THEN 'Proyecto en curso'
         WHEN fecha_final >= fecha_inicial THEN 'Fechas válidas'
         ELSE 'ERROR: Fechas inválidas'
       END AS validacion_fechas
FROM proyecto
WHERE presupuesto >= 0 AND horas >= 0
ORDER BY proyecto_id;

-- =============================================================================================================
-- SECCIÓN 15: ESTADÍSTICAS Y ANÁLISIS FINAL
-- =============================================================================================================

-- ESTADÍSTICAS GENERALES DEL SISTEMA
SELECT 'ESTADÍSTICAS GENERALES' AS seccion;
SELECT 
  (SELECT COUNT(*) FROM docente) AS total_docentes,
  (SELECT COUNT(*) FROM proyecto) AS total_proyectos,
  (SELECT COUNT(*) FROM docente WHERE tipo_docente = 'Tiempo completo') AS docentes_tiempo_completo,
  (SELECT COUNT(*) FROM docente WHERE tipo_docente = 'Cátedra') AS docentes_catedra,
  (SELECT COALESCE(SUM(presupuesto), 0) FROM proyecto) AS presupuesto_total_proyectos,
  (SELECT COALESCE(SUM(horas), 0) FROM proyecto) AS horas_total_proyectos;

-- DOCENTES CON MAYOR EXPERIENCIA
SELECT 'TOP 3 DOCENTES CON MAYOR EXPERIENCIA' AS seccion;
SELECT nombres, anios_experiencia, titulo, tipo_docente
FROM docente
ORDER BY anios_experiencia DESC
LIMIT 3;

-- PROYECTOS CON MAYOR PRESUPUESTO
USE proyectos_informaticos;
SELECT 'TOP 3 PROYECTOS CON MAYOR PRESUPUESTO' AS seccion;
SELECT p.nombre, p.presupuesto, d.nombres AS docente_jefe
FROM proyecto p
JOIN docente d ON p.docente_id_jefe = d.docente_id
ORDER BY p.presupuesto DESC
LIMIT 3;

-- =============================================================================================================
-- SECCIÓN 16: FUNCIONES AVANZADAS Y CONSULTAS ESPECIALIZADAS
-- =============================================================================================================

-- ============================================
-- FUNCIÓN 1: CALCULAR COSTO POR HORA DE PROYECTO
-- ============================================
-- Esta función calcula el costo por hora de un proyecto específico
-- dividiendo el presupuesto total entre las horas estimadas
-- Maneja casos especiales como proyectos con 0 horas para evitar división por cero

DROP FUNCTION IF EXISTS fn_costo_por_hora_proyecto;

DELIMITER $$
CREATE FUNCTION fn_costo_por_hora_proyecto(p_proyecto_id INT)
RETURNS DECIMAL(10,2)  -- Retorna el costo por hora como decimal con 2 decimales
DETERMINISTIC          -- El resultado es siempre el mismo para los mismos parámetros
READS SQL DATA         -- La función lee datos de la base de datos
BEGIN
    -- Variables locales para almacenar los valores del proyecto
    DECLARE v_presupuesto DECIMAL(12,2) DEFAULT 0;  -- Presupuesto del proyecto
    DECLARE v_horas INT DEFAULT 0;                  -- Horas del proyecto
    DECLARE v_costo_hora DECIMAL(10,2) DEFAULT 0;   -- Resultado del cálculo
    
    -- Obtener presupuesto y horas del proyecto específico
    -- IFNULL garantiza que si algún valor es NULL, se asigne 0
    SELECT IFNULL(presupuesto, 0), IFNULL(horas, 0) 
    INTO v_presupuesto, v_horas
    FROM proyecto 
    WHERE proyecto_id = p_proyecto_id;
    
    -- Validar que el proyecto existe (si no existe, ambos valores serán 0)
    IF v_presupuesto = 0 AND v_horas = 0 THEN
        RETURN 0;  -- Proyecto no encontrado
    END IF;
    
    -- Calcular costo por hora evitando división por cero
    IF v_horas > 0 THEN
        SET v_costo_hora = v_presupuesto / v_horas;
    ELSE
        SET v_costo_hora = 0;  -- Si no hay horas, el costo por hora es 0
    END IF;
    
    -- Retornar el resultado redondeado a 2 decimales
    RETURN ROUND(v_costo_hora, 2);
END$$

-- ============================================
-- FUNCIÓN 2: CONTAR PROYECTOS POR TIPO DE DOCENTE
-- ============================================
-- Esta función cuenta cuántos proyectos están liderados por docentes
-- de un tipo específico (Tiempo completo, Cátedra, etc.)

CREATE FUNCTION fn_contar_proyectos_por_tipo_docente(p_tipo_docente VARCHAR(40))
RETURNS INT            -- Retorna un número entero
DETERMINISTIC          -- Resultado consistente para los mismos parámetros
READS SQL DATA         -- Lee datos de múltiples tablas
BEGIN
    DECLARE v_contador INT DEFAULT 0;  -- Variable para almacenar el resultado
    
    -- Contar proyectos usando JOIN entre proyecto y docente
    -- Filtra por el tipo de docente especificado
    SELECT COUNT(p.proyecto_id) INTO v_contador
    FROM proyecto p
    INNER JOIN docente d ON p.docente_id_jefe = d.docente_id
    WHERE d.tipo_docente = p_tipo_docente;
    
    -- Retornar el contador (0 si no hay coincidencias)
    RETURN IFNULL(v_contador, 0);
END$$

-- ============================================
-- FUNCIÓN 3: OBTENER STATUS DEL PROYECTO
-- ============================================
-- Esta función determina el estado actual de un proyecto basándose en las fechas
-- Retorna: 'No iniciado', 'En curso', 'Finalizado', 'Vencido' o 'No encontrado'

CREATE FUNCTION fn_status_proyecto(p_proyecto_id INT)
RETURNS VARCHAR(50)    -- Retorna una cadena descriptiva del estado
READS SQL DATA         -- Lee datos de la tabla proyecto
BEGIN
    -- Variables para almacenar las fechas del proyecto
    DECLARE v_fecha_inicial DATE;
    DECLARE v_fecha_final DATE;
    DECLARE v_fecha_actual DATE DEFAULT CURDATE();  -- Fecha actual del sistema
    DECLARE v_status VARCHAR(50);
    
    -- Obtener las fechas del proyecto
    SELECT fecha_inicial, fecha_final 
    INTO v_fecha_inicial, v_fecha_final
    FROM proyecto 
    WHERE proyecto_id = p_proyecto_id;
    
    -- Verificar si el proyecto existe
    IF v_fecha_inicial IS NULL THEN
        RETURN 'No encontrado';
    END IF;
    
    -- Lógica para determinar el estado del proyecto
    IF v_fecha_actual < v_fecha_inicial THEN
        -- El proyecto aún no ha comenzado
        SET v_status = 'No iniciado';
    ELSEIF v_fecha_final IS NULL THEN
        -- El proyecto no tiene fecha final definida, está en curso
        SET v_status = 'En curso (sin fecha límite)';
    ELSEIF v_fecha_actual <= v_fecha_final THEN
        -- El proyecto está dentro del rango de fechas planificado
        SET v_status = 'En curso';
    ELSE
        -- La fecha actual es posterior a la fecha final
        SET v_status = 'Finalizado/Vencido';
    END IF;
    
    RETURN v_status;
END$$

DELIMITER ;

-- =============================================================================================================
-- SECCIÓN 16: CONSULTAS DE VERIFICACIÓN Y ANÁLISIS CON LAS NUEVAS FUNCIONES
-- =============================================================================================================

-- CONSULTA 1: Listado de todos los docentes y sus datos
SELECT 'LISTADO COMPLETO DE DOCENTES' AS seccion;
SELECT docente_id, numero_documento, nombres, titulo, anios_experiencia, direccion, tipo_docente
FROM docente
ORDER BY docente_id;

-- CONSULTA 2: Proyectos con información de sus docentes líderes
SELECT 'PROYECTOS Y SUS DOCENTES LÍDERES' AS seccion;
SELECT p.proyecto_id, p.nombre AS proyecto, p.presupuesto, p.horas, d.nombres AS docente_jefe
FROM proyecto p
JOIN docente d ON d.docente_id = p.docente_id_jefe
ORDER BY p.proyecto_id;

-- CONSULTA 3: Promedio de presupuesto por docente usando la UDF original
SELECT 'PROMEDIO DE PRESUPUESTO POR DOCENTE (UDF ORIGINAL)' AS seccion;
SELECT d.docente_id, d.nombres,
       fn_promedio_presupuesto_por_docente(d.docente_id) AS promedio_presupuesto
FROM docente d
ORDER BY promedio_presupuesto DESC;

-- CONSULTA 4: NUEVA - Costo por hora de cada proyecto usando la función nueva
SELECT 'COSTO POR HORA DE TODOS LOS PROYECTOS (FUNCIÓN NUEVA)' AS seccion;
SELECT 
    p.proyecto_id,
    p.nombre AS proyecto,
    p.presupuesto AS 'Presupuesto (COP)',
    p.horas AS 'Horas Estimadas',
    fn_costo_por_hora_proyecto(p.proyecto_id) AS 'Costo por Hora (COP)',
    d.nombres AS docente_jefe
FROM proyecto p
JOIN docente d ON p.docente_id_jefe = d.docente_id
ORDER BY fn_costo_por_hora_proyecto(p.proyecto_id) DESC;

-- CONSULTA 5: NUEVA - Conteo de proyectos por tipo de docente usando función nueva
SELECT 'PROYECTOS POR TIPO DE DOCENTE (FUNCIÓN NUEVA)' AS seccion;
SELECT 
    'Tiempo completo' AS 'Tipo Docente',
    fn_contar_proyectos_por_tipo_docente('Tiempo completo') AS 'Cantidad Proyectos'
UNION ALL
SELECT 
    'Cátedra' AS 'Tipo Docente',
    fn_contar_proyectos_por_tipo_docente('Cátedra') AS 'Cantidad Proyectos';

-- CONSULTA 6: NUEVA - Estado actual de todos los proyectos usando función nueva
SELECT 'ESTADO ACTUAL DE TODOS LOS PROYECTOS (FUNCIÓN NUEVA)' AS seccion;
SELECT 
    p.proyecto_id,
    p.nombre AS proyecto,
    p.fecha_inicial AS 'Fecha Inicio',
    p.fecha_final AS 'Fecha Fin',
    fn_status_proyecto(p.proyecto_id) AS 'Estado Actual',
    d.nombres AS docente_jefe
FROM proyecto p
JOIN docente d ON p.docente_id_jefe = d.docente_id
ORDER BY p.fecha_inicial;

-- CONSULTA 7: Verificación de auditoría de actualizaciones
SELECT 'AUDITORÍA DE ACTUALIZACIONES' AS seccion;
SELECT * FROM copia_actualizados_docente
ORDER BY auditoria_id DESC;

-- CONSULTA 8: Verificación de auditoría de eliminaciones
SELECT 'AUDITORÍA DE ELIMINACIONES' AS seccion;
SELECT * FROM copia_eliminados_docente
ORDER BY auditoria_id DESC;

-- CONSULTA 9: Docentes con sus proyectos (incluyendo docentes sin proyectos)
SELECT 'DOCENTES Y SUS PROYECTOS (LEFT JOIN)' AS seccion;
SELECT d.docente_id, d.nombres, 
       COALESCE(p.proyecto_id, 0) AS proyecto_id, 
       COALESCE(p.nombre, 'Sin proyectos asignados') AS proyecto
FROM docente d
LEFT JOIN proyecto p ON d.docente_id = p.docente_id_jefe
ORDER BY d.docente_id, p.proyecto_id;

-- CONSULTA 10: Total de horas y presupuesto por docente con análisis de eficiencia
SELECT 'RESUMEN DE HORAS, PRESUPUESTO Y EFICIENCIA POR DOCENTE' AS seccion;
SELECT d.docente_id, d.nombres, 
       COUNT(p.proyecto_id) AS num_proyectos,
       COALESCE(SUM(p.horas), 0) AS total_horas,
       COALESCE(SUM(p.presupuesto), 0) AS total_presupuesto,
       -- Usando las nuevas funciones para análisis adicional
       CASE 
         WHEN SUM(p.horas) > 0 THEN ROUND(SUM(p.presupuesto) / SUM(p.horas), 2)
         ELSE 0
       END AS costo_promedio_por_hora
FROM docente d
LEFT JOIN proyecto p ON d.docente_id = p.docente_id_jefe
GROUP BY d.docente_id, d.nombres
ORDER BY total_presupuesto DESC;

-- CONSULTA 11: Validación de restricciones CHECK con estado de proyectos
SELECT 'VALIDACIÓN DE RESTRICCIONES Y ESTADOS' AS seccion;
SELECT proyecto_id, nombre, fecha_inicial, fecha_final, presupuesto, horas,
       fn_status_proyecto(proyecto_id) AS estado_actual,
       fn_costo_por_hora_proyecto(proyecto_id) AS costo_por_hora,
       CASE 
         WHEN fecha_final IS NULL THEN 'Proyecto en curso'
         WHEN fecha_final >= fecha_inicial THEN 'Fechas válidas'
         ELSE 'ERROR: Fechas inválidas'
       END AS validacion_fechas
FROM proyecto
WHERE presupuesto >= 0 AND horas >= 0
ORDER BY proyecto_id;

-- =============================================================================================================
-- SECCIÓN 17: ESTADÍSTICAS Y ANÁLISIS FINAL CON NUEVAS FUNCIONES
-- =============================================================================================================

-- ESTADÍSTICAS GENERALES DEL SISTEMA
SELECT 'ESTADÍSTICAS GENERALES DEL SISTEMA' AS seccion;
SELECT 
  (SELECT COUNT(*) FROM docente) AS total_docentes,
  (SELECT COUNT(*) FROM proyecto) AS total_proyectos,
  (SELECT COUNT(*) FROM docente WHERE tipo_docente = 'Tiempo completo') AS docentes_tiempo_completo,
  (SELECT COUNT(*) FROM docente WHERE tipo_docente = 'Cátedra') AS docentes_catedra,
  (SELECT fn_contar_proyectos_por_tipo_docente('Tiempo completo')) AS proyectos_tiempo_completo,
  (SELECT fn_contar_proyectos_por_tipo_docente('Cátedra')) AS proyectos_catedra,
  (SELECT COALESCE(SUM(presupuesto), 0) FROM proyecto) AS presupuesto_total_proyectos,
  (SELECT COALESCE(SUM(horas), 0) FROM proyecto) AS horas_total_proyectos;

-- DOCENTES CON MAYOR EXPERIENCIA
SELECT 'TOP 3 DOCENTES CON MAYOR EXPERIENCIA' AS seccion;
SELECT nombres, anios_experiencia, titulo, tipo_docente,
       fn_contar_proyectos_por_tipo_docente(tipo_docente) AS proyectos_su_tipo
FROM docente
ORDER BY anios_experiencia DESC
LIMIT 3;

-- PROYECTOS CON MAYOR PRESUPUESTO Y SU ANÁLISIS DE EFICIENCIA
SELECT 'TOP 3 PROYECTOS CON MAYOR PRESUPUESTO Y ANÁLISIS' AS seccion;
SELECT p.nombre, 
       FORMAT(p.presupuesto, 2) AS presupuesto_formateado,
       p.horas,
       fn_costo_por_hora_proyecto(p.proyecto_id) AS costo_por_hora,
       fn_status_proyecto(p.proyecto_id) AS estado_actual,
       d.nombres AS docente_jefe
FROM proyecto p
JOIN docente d ON p.docente_id_jefe = d.docente_id
ORDER BY p.presupuesto DESC
LIMIT 3;

-- ANÁLISIS DE EFICIENCIA: Proyectos más y menos eficientes
SELECT 'ANÁLISIS DE EFICIENCIA: PROYECTOS MÁS Y MENOS EFICIENTES' AS seccion;
SELECT 
    'PROYECTOS MÁS EFICIENTES (menor costo por hora)' AS tipo_analisis,
    p.nombre AS proyecto,
    fn_costo_por_hora_proyecto(p.proyecto_id) AS costo_por_hora,
    d.nombres AS docente_jefe
FROM proyecto p
JOIN docente d ON p.docente_id_jefe = d.docente_id
WHERE p.horas > 0  -- Solo proyectos con horas definidas
ORDER BY fn_costo_por_hora_proyecto(p.proyecto_id) ASC
LIMIT 2

UNION ALL

SELECT 
    'PROYECTOS MENOS EFICIENTES (mayor costo por hora)' AS tipo_analisis,
    p.nombre AS proyecto,
    fn_costo_por_hora_proyecto(p.proyecto_id) AS costo_por_hora,
    d.nombres AS docente_jefe
FROM proyecto p
JOIN docente d ON p.docente_id_jefe = d.docente_id
WHERE p.horas > 0  -- Solo proyectos con horas definidas
ORDER BY fn_costo_por_hora_proyecto(p.proyecto_id) DESC
LIMIT 2;

-- =============================================================================================================
-- FIN DEL SCRIPT
-- =============================================================================================================
-- Este script ha creado exitosamente:
-- 1. Base de datos proyectos_informaticos
-- 2. Tablas principales: docente y proyecto
-- 3. Tablas de auditoría: copia_actualizados_docente y copia_eliminados_docente
-- 4. Procedimientos almacenados CRUD para docentes y proyectos (8 procedimientos)
-- 5. Funciones UDF:
--    - fn_promedio_presupuesto_por_docente() [ORIGINAL]
--    - fn_costo_por_hora_proyecto() [NUEVA]
--    - fn_contar_proyectos_por_tipo_docente() [NUEVA]
--    - fn_status_proyecto() [NUEVA]
-- 6. Triggers automáticos para auditoría
-- 7. Índices para optimización
-- 8. 8 docentes de ejemplo (2 originales + 6 adicionales solicitados)
-- 9. 8 proyectos correspondientes
-- 10. Consultas de verificación y análisis (incluyendo uso de nuevas funciones)
-- 
-- NUEVAS FUNCIONALIDADES AGREGADAS:
-- ================================
-- 1. fn_costo_por_hora_proyecto(): Calcula el costo por hora de cualquier proyecto
-- 2. fn_contar_proyectos_por_tipo_docente(): Cuenta proyectos según tipo de docente
-- 3. fn_status_proyecto(): Determina el estado actual de un proyecto basándose en fechas
--
-- El sistema está listo para ser utilizado en un entorno de gestión de proyectos informáticos.
-- =============================================================================================================
