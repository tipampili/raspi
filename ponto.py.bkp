import requests
import json
import datetime
import tkinter as tk
import sqlite3

class PontoGUI(tk.Tk):
    def __init__(self):
        super().__init__()
        self.attributes("-fullscreen", True)
        self.title("Coletor de Ponto")

        self.img = tk.PhotoImage(file="/home/pi/raspi/pam1.png")
        self.image_label = tk.Label(self, image=self.img)
        self.image_label.pack()
        self.time_label = tk.Label(self, font=("Arial", 35))
        self.time_label.pack()
        self.update_time()
        self.status_label = tk.Label(self, text="Aproxime o Chachá...", font=("Arial", 30), fg="#F400A1", anchor="w", wraplength=450)
        self.status_label.pack(pady=20)
        self.numero = ""
        self.bind("<Key>", self.key_pressed)

        self.ultimo_horario_batida = None

        self.funcionarios = {}
        self.atualizar_dados_apex()

        self.db_conn = sqlite3.connect("ponto_database.db")
        self.create_table_if_not_exists()

    def create_table_if_not_exists(self):
        cursor = self.db_conn.cursor()
        cursor.execute(
            '''
            CREATE TABLE IF NOT EXISTS ponto_data (
                cracha TEXT,
                horario TEXT
            )
            '''
        )

        cursor.execute(
            '''
            CREATE TABLE IF NOT EXISTS dados_totais (
                cracha TEXT,
                horario TEXT
            )
            '''
        )

        self.db_conn.commit()

    def update_time(self):
        current_time = datetime.datetime.now().strftime("%H:%M:%S")
        self.time_label.config(text=current_time)
        self.after(1000, self.update_time)

    def key_pressed(self, event):
        if event.char.isnumeric() and len(self.numero) < 9:
            self.numero += event.char
            self.status_label.config(text=self.numero)
        elif event.keysym == "Return":
            if len(self.numero) <= 8:
                self.enviar_dados_apex_oracle()
            else:
                print("Número inválido")
                self.numero = ""
                self.after(1000, lambda: self.status_label.config(text="Aproxime o Chachá..."))

    def verificar_conexao_internet(self):
        try:
            requests.get("https://www.google.com")
            return True
        except:
            return False

    def atualizar_dados_apex(self):
        if self.verificar_conexao_internet() and self.verificar_tempo_minimo():
            print("Foram atualizados os dados do apex")
            url = "https://apex.pampili.com.br/ords/afvserver/rm/funcionarios?key=PontoPampili@)@!&coligada=1&filial=7"
            headers = {
                'Content-Type': 'application/json'
            }
            response = requests.get(url, headers=headers)
            if response.status_code == 200:
                data = response.json()
                funcionarios = data['items']
                self.funcionarios = {funcionario['cracha']: funcionario['nome'] for funcionario in funcionarios}
                print("Dados do Apex atualizados.")
        self.after(900000, self.atualizar_dados_apex)

    def gravar_dados_no_banco(self, cracha, horario):
        cursor = self.db_conn.cursor()
        cursor.execute("INSERT INTO ponto_data (cracha, horario) VALUES (?, ?)", (cracha, horario))
        cursor.execute("INSERT INTO dados_totais (cracha, horario) VALUES (?, ?)", (cracha, horario))
        self.ultimo_horario_batida = datetime.datetime.now()
        self.db_conn.commit()

    def enviar_dados_para_apex(self):
        print(self.ultimo_horario_batida)
        if self.verificar_conexao_internet() and self.verificar_tempo_minimo():
            cursor = self.db_conn.cursor()
            cursor.execute("SELECT * FROM ponto_data")
            dados = cursor.fetchall()

            url = 'https://apex.pampili.com.br/ords/afvserver/ponto/pontoparanaiba'
            headers = {'Content-type': 'application/json'}
            linhas_mantidas = []

            for linha in dados:
                payload = {
                    "cracha": linha[0],
                    "horario": linha[1]
                }
                json_payload = json.dumps(payload)

                response = requests.post(url, data=json_payload, headers=headers)

                if response.status_code == 200:
                    print(f"Dado {linha} enviado com sucesso para o sistema no Apex Oracle.")

                    cursor.execute("DELETE FROM ponto_data WHERE cracha = ? AND horario = ?", (linha[0], linha[1]))
                else:
                    print(f"Falha ao enviar dado {linha}. Status Code: {response.status_code}")
                    linhas_mantidas.append(linha)

            self.db_conn.commit()
        else:
            print("Aguardando tempo mínimo ou sem conexão com a internet...")
            #self.after(550000, self.enviar_dados_para_apex)

    def enviar_dados_apex_oracle(self):
        horario = datetime.datetime.now().strftime(f'%d%m%y%H%M')

        nome_funcionario = self.funcionarios.get(self.numero)

        if nome_funcionario:
            self.status_label.config(
                text=f"{nome_funcionario}", background="green", fg="#FFFFFF", font=("Arial", 30, "bold"))
            self.configure(background="green")

        else:
            self.status_label.config(
                text="Ponto registrado!", background="green", fg="#FFFFFF", font=("Arial", 30, "bold"))
            self.configure(background="green")

        self.after(700, lambda: self.status_label.config(
            text="Aproxime o Chachá...", background="#F0F0F0", fg="#F400A1"))
        self.after(700, lambda: self.configure(background="#F0F0F0"))

        self.gravar_dados_no_banco(self.numero, horario)
        self.numero = ""

    def verificar_tempo_minimo(self):

        if self.ultimo_horario_batida is None:
            return True

        tempo_atual = datetime.datetime.now()
        ultimo_horario = self.ultimo_horario_batida
        print(f"tempo atual = {tempo_atual} e ultimo hor {ultimo_horario}")
        diferenca = tempo_atual - ultimo_horario
        print(f"Diferença {diferenca}")
        return diferenca.total_seconds() >= 900


if __name__ == "__main__":
    app = PontoGUI()

    def on_close():
        app.db_conn.close()
        app.destroy()

    app.protocol("WM_DELETE_WINDOW", on_close)

    def enviar_dados_apex_apos_15m():
        app.enviar_dados_para_apex()
        app.after(900000, enviar_dados_apex_apos_15m)

    app.after(900000, enviar_dados_apex_apos_15m)
    app.mainloop()
