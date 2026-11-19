CREATE TABLE Proveedor (
    ID_pro INTEGER PRIMARY KEY,
    nombre_empresa VARCHAR(75) NOT NULL
);

CREATE TABLE Material (
    ID_mat INTEGER PRIMARY KEY,
    Stock INTEGER NOT NULL DEFAULT 0 CHECK (Stock >= 0),
    Nombre VARCHAR(75) NOT NULL
);

CREATE TABLE Vela (
    ID_vela INTEGER PRIMARY KEY,
    Nombre VARCHAR(75) NOT NULL,
    Precio INTEGER NOT NULL CHECK (Precio >= 0),
    Stock INTEGER NOT NULL DEFAULT 0 CHECK (Stock >= 0)
);

CREATE TABLE Cliente (
    ID_cliente INTEGER PRIMARY KEY,
    Nombre VARCHAR(100) NOT NULL
);

CREATE TABLE Origen (
    ID_pro INTEGER REFERENCES Proveedor(ID_pro),
    ID_mat INTEGER REFERENCES Material(ID_mat),
    Precio INTEGER NOT NULL CHECK (Precio >= 0),
    PRIMARY KEY (ID_pro, ID_mat)
);

CREATE TABLE Receta (
    ID_mat INT REFERENCES Material(ID_mat),
    ID_vela INT REFERENCES Vela(ID_vela),
    Gramos INTEGER NOT NULL CHECK (Gramos > 0),
    PRIMARY KEY (ID_mat, ID_vela)
);

CREATE TABLE Venta (
    ID_venta INT PRIMARY KEY,
    ID_cliente INT REFERENCES Cliente(ID_cliente), -- Permite NULL para ventas en feria
    Fecha TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE Detalle_Venta (
    ID_vela INTEGER REFERENCES Vela(ID_vela),
    ID_venta INTEGER REFERENCES Venta(ID_venta),
    Cant_velas INTEGER NOT NULL CHECK (Cant_velas > 0),
    precio_unitario INTEGER not null check (precio_unitario >= 0),
    PRIMARY KEY (ID_vela, ID_venta)
);

CREATE TABLE Boleta (
    ID_venta INT REFERENCES Venta(ID_venta) PRIMARY KEY,
    Medio_Pago VARCHAR(50) NOT NULL,
    canal_venta VARCHAR(50) NOT NULL CHECK (canal_venta IN ('Online', 'Feria')),
    monto_total INTEGER NOT NULL DEFAULT 0 CHECK (monto_total >= 0)
);


CREATE OR REPLACE FUNCTION FN_Validar_stock_Registrar_precioHistorico() --Validar si compra > stock y registrar precio en el momento de la compra
RETURNS TRIGGER AS $$
DECLARE
    v_stock_disponible INT;
    v_precio_actual INT;
BEGIN
    -- Obtenemos el stock y precio actual de la vela desde la tabla Vela
    SELECT Stock, Precio --Seleccionar valores
    INTO v_stock_disponible, v_precio_actual --Hacia
    FROM Vela --Desde
    WHERE ID_vela = NEW.ID_vela; -- Donde

    IF NOT FOUND THEN --Si no se encuentra esa vela, cancela la operacion
        RAISE EXCEPTION 'La vela con ID % no existe.', NEW.ID_vela;
    END IF;

    -- Si es un UPDATE sobre la misma vela, sumamos la cantidad previa al stock disponible
    --TG_OP = TRigger OPeration
    --Sumar la cantidad previa a la variable temporal para calcular lo disponible
    IF TG_OP = 'UPDATE' AND OLD.ID_vela = NEW.ID_vela THEN
        v_stock_disponible := v_stock_disponible + OLD.Cant_velas;
    END IF;

    -- Restricción de integridad, impedir ventas que superen el stock disponible
    IF NEW.Cant_velas > v_stock_disponible THEN
        RAISE EXCEPTION 'Stock insuficiente para la vela ID % (solicitado: %, disponible: %).',
            NEW.ID_vela, NEW.Cant_velas, v_stock_disponible;
    END IF;

    -- Registrar automáticamente el precio histórico al momento de insertar
    IF TG_OP = 'INSERT' THEN
        NEW.precio_unitario := v_precio_actual;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER TG_Validar_stock_Registrar_precioHistorico --Crear trigger
BEFORE INSERT OR UPDATE ON Detalle_Venta --Antes de insertar o al Actualizar Detalle_Venta
FOR EACH row --Para cada fila
EXECUTE FUNCTION FN_Validar_stock_Registrar_precioHistorico(); --Ejecutar funcion


CREATE OR REPLACE FUNCTION FN_ActStockVelas()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN --Si se vende algo, se resta stock de velas
        UPDATE Vela
        SET Stock = Stock - NEW.Cant_velas
        WHERE ID_vela = NEW.ID_vela;
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN --Si cambia la cantidad pero no la vela, se actualiza el cambio. Si no (vela distinta) se devuelve la original y resta la otra
        IF OLD.ID_vela = NEW.ID_vela THEN
            UPDATE Vela
            SET Stock = Stock + OLD.Cant_velas - NEW.Cant_velas
            WHERE ID_vela = NEW.ID_vela;
        ELSE
            UPDATE Vela SET Stock = Stock + OLD.Cant_velas WHERE ID_vela = OLD.ID_vela;
            UPDATE Vela SET Stock = Stock - NEW.Cant_velas WHERE ID_vela = NEW.ID_vela;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN --Si una vela es borrada de la venta, se devuelve stock
        UPDATE Vela
        SET Stock = Stock + OLD.Cant_velas
        WHERE ID_vela = OLD.ID_vela;
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER TG_ActStockVelas --Crear trigger
AFTER INSERT OR UPDATE OR DELETE ON Detalle_Venta --Despues de insertar o actualizar o borrar en Detalle_Venta
FOR EACH ROW
EXECUTE FUNCTION FN_ActStockVelas();


CREATE OR REPLACE PROCEDURE SP_ActualizarBoleta(
    p_id_venta INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_calculado INT;
    v_canal VARCHAR(50);
    v_id_cliente INT;
BEGIN
    SELECT b.canal_venta, v.ID_cliente
    INTO v_canal, v_id_cliente
    FROM Boleta b
    JOIN Venta v ON b.ID_venta = v.ID_venta
    WHERE b.ID_venta = p_id_venta;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe una boleta registrada para la venta ID %.', p_id_venta;
    END IF;

    SELECT COALESCE(SUM(Cant_velas * precio_unitario), 0)
    INTO v_total_calculado
    FROM Detalle_Venta
    WHERE ID_venta = p_id_venta;

    UPDATE Boleta
    SET monto_total = v_total_calculado
    WHERE ID_venta = p_id_venta;

    IF v_total_calculado = 0 THEN
        ROLLBACK;
        RAISE NOTICE 'ROLLBACK ejecutado: la venta % no tiene productos en Detalle_Venta.', p_id_venta;
        RETURN;
    END IF;

    IF v_canal = 'Online' AND v_id_cliente IS NULL THEN
        ROLLBACK;
        RAISE NOTICE 'ROLLBACK ejecutado: una venta Online (ID %) requiere un cliente registrado.', p_id_venta;
        RETURN;
    END IF;

    COMMIT;
    RAISE NOTICE 'Boleta de venta % actualizada correctamente. Total: $%', p_id_venta, v_total_calculado;
END;
$$;

CREATE OR REPLACE PROCEDURE SP_CalcularKPIs(
    IN vela_id INT,
    IN fecha_inicial TIMESTAMP,
    IN fecha_fin TIMESTAMP,
    OUT nombre_vela VARCHAR,
    OUT ganancia_unitaria INTEGER,
    OUT vela_mas_vendida VARCHAR,
    OUT total_vendido BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    precio_actual INT;
    costo_materiales NUMERIC;
BEGIN
    -- KPI 1: Buscar datos de la vela y validar que exista
    SELECT Nombre, Precio
    INTO nombre_vela, precio_actual
    FROM Vela
    WHERE ID_vela = vela_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La vela con ID % no existe.', vela_id;
    END IF;

    -- Calcular costo de producción según gramos de la receta y precio promedio del material
    SELECT COALESCE(SUM(r.Gramos * o.precio_prom), 0)
    INTO costo_materiales
    FROM Receta r
    JOIN (
        SELECT ID_mat, AVG(Precio) AS precio_prom
        FROM Origen
        GROUP BY ID_mat
    ) o ON r.ID_mat = o.ID_mat
    WHERE r.ID_vela = vela_id;

    ganancia_unitaria := ROUND(precio_actual - costo_materiales)::INTEGER;

    -- KPI 2: Obtener la vela más vendida en el rango de fechas
    SELECT ve.Nombre, COALESCE(SUM(dv.Cant_velas), 0)
    INTO vela_mas_vendida, total_vendido
    FROM Venta v
    JOIN Detalle_Venta dv ON v.ID_venta = dv.ID_venta
    JOIN Vela ve ON dv.ID_vela = ve.ID_vela
    WHERE v.Fecha BETWEEN fecha_inicial AND fecha_fin
    GROUP BY ve.ID_vela, ve.Nombre
    ORDER BY SUM(dv.Cant_velas) DESC
    LIMIT 1;
END;
$$;


-- Tablas Independientes
INSERT INTO Proveedor (ID_pro, nombre_empresa) VALUES
(1, 'Insumos Artesanales del Sur SpA'),
(2, 'Ceras y Esencias Cordillera Ltda.'),
(3, 'Distribuidora Aromas Naturales'),
(4, 'Envases y Pabilos Santiago');

INSERT INTO Material (ID_mat, Stock, Nombre) VALUES
(1, 15000, 'Cera de soya bajo punto de fusión'),
(2, 3000,  'Esencia aromática de vainilla'),
(3, 2500,  'Esencia aromática de lavanda'),
(4, 2000,  'Esencia cítrica naranja-canela'),
(5, 5000,  'Pabilo de algodón encerado');

INSERT INTO Vela (ID_vela, Nombre, Precio, Stock) VALUES
(1, 'Vela Vainilla Dulce',      6500, 30),
(2, 'Vela Lavanda Relajante',   7000, 25),
(3, 'Vela Canela y Naranja',    7500, 20),
(4, 'Vela Eucalipto Fresco',    6000, 35),
(5, 'Vela Bosque de Pino',      8500, 15);

INSERT INTO Cliente (ID_cliente, Nombre) VALUES
(1, 'Juan Perez'),
(2, 'Matias Fernandez'),
(3, 'Joaquin Rojas'),
(4, 'Sebastian Portales'),
(5, 'Diego Lopez'),
(6, 'Ana Garcia');

-- Tablas Dependientes
-- Precio expresado por gramo en CLP para que coincida con Receta.Gramos
INSERT INTO Origen (ID_pro, ID_mat, Precio) VALUES
(1, 1, 12), -- Cera de soya proveedor 1 ($12/g)
(2, 1, 14), -- Cera de soya proveedor 2 ($14/g -> promedio $13/g)
(2, 2, 45), -- Esencia vainilla ($45/g)
(3, 3, 50), -- Esencia lavanda ($50/g)
(3, 4, 48), -- Esencia naranja-canela ($48/g)
(4, 5, 20); -- Pabilo ($20/g)

-- Recetas (gramos de cada material necesarios para fabricar 1 vela)
INSERT INTO Receta (ID_mat, ID_vela, Gramos) VALUES
(1, 1, 180), (2, 1, 15), (5, 1, 5), -- Vela 1: 180g cera + 15g vainilla + 5g pabilo
(1, 2, 180), (3, 2, 15), (5, 2, 5), -- Vela 2: 180g cera + 15g lavanda + 5g pabilo
(1, 3, 195), (4, 3, 20), (5, 3, 5), -- Vela 3: 195g cera + 20g canela-naranja + 5g pabilo
(1, 4, 165), (3, 4, 10), (5, 4, 5), -- Vela 4: 165g cera + 10g esencia + 5g pabilo
(1, 5, 225), (4, 5, 20), (5, 5, 5); -- Vela 5: 225g cera + 20g esencia + 5g pabilo

-- Ventas (ID_cliente NULL representa ventas anónimas en feria presencial)
INSERT INTO Venta (ID_venta, ID_cliente, Fecha) VALUES
(1,  1,    '2026-09-10 14:30:00'),
(2,  2,    '2026-09-18 18:15:00'),
(3,  NULL, '2026-09-26 12:00:00'),
(4,  3,    '2026-10-04 20:45:00'),
(5,  NULL, '2026-10-11 16:20:00'),
(6,  4,    '2026-10-19 11:10:00'),
(7,  5,    '2026-10-28 19:05:00'),
(8,  NULL, '2026-11-02 15:40:00'),
(9,  6,    '2026-11-08 21:00:00'),
(10, NULL, '2026-11-14 13:25:00');


-- Ventas y Boletas
-- Los triggers completan precio_unitario y descuentan Vela.Stock automáticamente
INSERT INTO Detalle_Venta (ID_vela, ID_venta, Cant_velas) VALUES
(1, 1, 2), (2, 1, 1),
(3, 2, 2),
(1, 3, 3), (4, 3, 2),
(2, 4, 2), (5, 4, 1),
(1, 5, 1), (3, 5, 1),
(4, 6, 3),
(1, 7, 2), (2, 7, 2), (3, 7, 1),
(5, 8, 2),
(2, 9, 2), (4, 9, 1),
(1, 10, 2);

-- Boletas iniciadas en monto_total = 0 para calcularlas con el SP
INSERT INTO Boleta (ID_venta, Medio_Pago, canal_venta) VALUES
(1,  'Transferencia', 'Online'),
(2,  'Débito',        'Online'),
(3,  'Efectivo',      'Feria'),
(4,  'Transferencia', 'Online'),
(5,  'Débito',        'Feria'),
(6,  'Crédito',       'Online'),
(7,  'Transferencia', 'Online'),
(8,  'Efectivo',      'Feria'),
(9,  'Débito',        'Online'),
(10, 'Efectivo',      'Feria');

-- Actualizamos el monto_total de las 10 boletas usando el Stored Procedure
CALL SP_ActualizarBoleta(1);
CALL SP_ActualizarBoleta(2);
CALL SP_ActualizarBoleta(3);
CALL SP_ActualizarBoleta(4);
CALL SP_ActualizarBoleta(5);
CALL SP_ActualizarBoleta(6);
CALL SP_ActualizarBoleta(7);
CALL SP_ActualizarBoleta(8);
CALL SP_ActualizarBoleta(9);
CALL SP_ActualizarBoleta(10);
