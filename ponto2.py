#!/usr/bin/env python3
import tkinter as tk
import sqlite3
import datetime
import requests
import logging
import threading

# Configuration
DB_PATH = "/home/pi/raspi/ponto_database.db"
LOG_PATH = "/home/pi/raspi/ponto_sync.log"
APEX_URL = "https://apex.pampili.com.br/ords/afvserver/ponto/pontoparanaiba"  # substitua pela sua URL
HEADERS = {"Content-Type": "application/json"}

SYNC_INTERVAL_SECONDS = 900  # 15 minutes
RETRY_ATTEMPTS = 3
RETRY_BACKOFF = 2  # exponential backoff factor

# Setup logging
logging.basicConfig(
    filename=LOG_PATH,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s: %(message)s"
)

class PontoApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Registro de Ponto")

        # Database setup
        self.db_conn = sqlite3.connect(DB_PATH, check_same_thread=False)
        self.db_conn.execute("PRAGMA journal_mode=WAL;")
        self.db_conn.execute("""
            CREATE TABLE IF NOT EXISTS ponto_data (
                cracha TEXT NOT NULL,
                horario TEXT NOT NULL
            )
        """)
        self.db_conn.commit()

        # Last sync timestamp
        self.ultimo_sync = datetime.datetime.min

        # UI elements
        self.label = tk.Label(self, text="Matrícula (crachá):")
        self.label.pack(padx=10, pady=5)
        self.entry = tk.Entry(self)
        self.entry.pack(padx=10, pady=5)
        self.button = tk.Button(self, text="Registrar Ponto", command=self.registrar_ponto)
        self.button.pack(padx=10, pady=10)

        # Schedule first sync
        self.after(60000, self.programar_sync)

        # Handle window close
        self.protocol("WM_DELETE_WINDOW", self.on_close)

    def registrar_ponto(self):
        cracha = self.entry.get().strip()
        if not cracha:
            logging.warning("Tentativa de gravar ponto sem matrícula.")
            return
        horario = datetime.datetime.now().isoformat()
        cursor = self.db_conn.cursor()
        cursor.execute("INSERT INTO ponto_data (cracha, horario) VALUES (?, ?)", (cracha, horario))
        self.db_conn.commit()
        logging.info(f"Batida salva local: {cracha} @ {horario}")
        self.entry.delete(0, tk.END)

    def verificar_conexao_internet(self):
        try:
            requests.get("https://www.google.com", timeout=5)
            return True
        except requests.RequestException:
            logging.warning("Sem conexão com a internet.")
            return False

    def verificar_intervalo_sync(self):
        diferenca = datetime.datetime.now() - self.ultimo_sync
        return diferenca.total_seconds() >= SYNC_INTERVAL_SECONDS

    def post_com_retry(self, payload):
        for tentativa in range(1, RETRY_ATTEMPTS + 1):
            try:
                resp = requests.post(APEX_URL, json=payload, headers=HEADERS, timeout=10)
                if 200 <= resp.status_code < 300:
                    return True
                else:
                    logging.warning(f"Resposta inesperada ({resp.status_code}) na tentativa {tentativa}.")
            except requests.RequestException as e:
                logging.error(f"Erro na tentativa {tentativa}: {e}")
            # Exponential backoff
            threading.Event().wait(RETRY_BACKOFF ** (tentativa - 1))
        return False

    def enviar_dados_para_apex(self):
        if not self.verificar_conexao_internet() or not self.verificar_intervalo_sync():
            return
        cursor = self.db_conn.cursor()
        cursor.execute("SELECT cracha, horario FROM ponto_data")
        registros = cursor.fetchall()
        for cracha, horario in registros:
            payload = {"cracha": cracha, "horario": horario}
            if self.post_com_retry(payload):
                cursor.execute("DELETE FROM ponto_data WHERE cracha=? AND horario=?", (cracha, horario))
                self.db_conn.commit()
                logging.info(f"Registro enviado: {cracha} @ {horario}")
            else:
                logging.error(f"Falha ao enviar: {cracha} @ {horario}")
        self.ultimo_sync = datetime.datetime.now()

    def programar_sync(self):
        threading.Thread(target=self.enviar_dados_para_apex, daemon=True).start()
        self.after(60000, self.programar_sync)

    def on_close(self):
        try:
            self.enviar_dados_para_apex()
        except Exception as e:
            logging.error(f"Erro ao enviar dados no fechamento: {e}")
        self.db_conn.close()
        self.destroy()

if __name__ == "__main__":
    app = PontoApp()
    app.mainloop()
