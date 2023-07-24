import requests
import json
import datetime
import tkinter as tk
import asyncio
from threading import Thread

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
        self.funcionarios = {}
        self.atualizar_dados_apex()
        self.dados = []

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
                self.armazenar_dados()
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
        if self.verificar_conexao_internet():
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
        self.after(550000, self.atualizar_dados_apex)

    def armazenar_dados(self):
        horario = datetime.datetime.now().strftime(f'%d%m%y%H%M')
        dados = f"{self.numero};{horario}\n"
        self.dados.append(dados)
        nome_funcionario = self.funcionarios.get(self.numero)

        if nome_funcionario:
            self.status_label.config(text=f"{nome_funcionario}", background="green", fg="#FFFFFF", font=("Arial", 30, "bold"))
            self.configure(background="green")
        else:
            self.status_label.config(text="Ponto registrado!", background="green", fg="#FFFFFF", font=("Arial", 30, "bold"))
            self.configure(background="green")

        self.after(700, lambda: self.configure(background="#F0F0F0"))
        self.after(700, lambda: self.status_label.config(text="Aproxime o Chachá...", background="#F0F0F0", fg="#F400A1"))

        self.numero = ""

    async def enviar_dados_periodicos(self):
        while True:
            await asyncio.sleep(3600) 

            if self.verificar_conexao_internet():
                dados_enviar = self.dados.copy()
                self.dados.clear()

                url = 'https://apex.pampili.com.br/ords/afvserver/ponto/pontoparanaiba'
                headers = {'Content-type': 'application/json'}

                for dado in dados_enviar:
                    campos = dado.strip().split(";")
                    payload = {
                        "cracha": campos[0],
                        "horario": campos[1]
                    }
                    json_payload = json.dumps(payload)

                    response = requests.post(url, data=json_payload, headers=headers)

                    if response.status_code == 200:
                        print(f"Dado {dado.strip()} enviado com sucesso para o sistema no Apex Oracle.")
                    else:
                        print(f"Falha ao enviar dado {dado.strip()}. Status Code: {response.status_code}")

            else:
                self.dados.extend(dados_enviar) 

    def iniciar_interface_grafica(self):
        self.mainloop()

    def iniciar_loop_async(self):
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.create_task(self.enviar_dados_periodicos())
        loop.run_forever()

if __name__ == "__main__":
    app = PontoGUI()

    def verificar_conexao_e_enviar_dados():
        if app.verificar_conexao_internet():
            with open("/home/pi/raspi/dados.txt", "r") as arquivo:
                dados = arquivo.readlines()
            if dados:
                Thread(target=app.enviar_dados, args=(dados,)).start()

        app.after(300000, verificar_conexao_e_enviar_dados)

    verificar_conexao_e_enviar_dados()

    Thread(target=app.iniciar_loop_async).start()
    app.iniciar_interface_grafica()
