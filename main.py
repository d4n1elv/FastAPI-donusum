from fastapi import FastAPI
import psycopg
from psycopg.rows import dict_row

app = FastAPI(title="API Proyecto BD - Pyme de Velas")

# Reemplaza 'nombre_bd' (y '1234' si tu clave de admin es distinta)
DB_URL = "postgresql://admin:1234@localhost:5432/proyecto"

def ejecutar_consulta(query: str):
    with psycopg.connect(DB_URL, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(query)
            return cur.fetchall()

@app.get("/")
def inicio():
    return {"estado": "API funcionando correctamente"}

@app.get("/velas")
def listar_velas():
    return ejecutar_consulta("SELECT * FROM Vela ORDER BY ID_vela;")

@app.get("/boletas")
def listar_boletas():
    return ejecutar_consulta("SELECT * FROM Boleta ORDER BY ID_venta;")

@app.get("/ventas")
def listar_ventas_detalle():
    sql = """
        SELECT v.ID_venta,
               v.Fecha,
               COALESCE(c.Nombre, 'Feria (Anónimo)') AS cliente,
               b.canal_venta,
               b.Medio_Pago,
               b.monto_total
        FROM Venta v
        LEFT JOIN Cliente c ON v.ID_cliente = c.ID_cliente
        JOIN Boleta b ON v.ID_venta = b.ID_venta
        ORDER BY v.ID_venta;
    """
    return ejecutar_consulta(sql)
