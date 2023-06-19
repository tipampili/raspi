import requests
import json
import datetime
import tkinter as tk

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
        #self.status_label = tk.Label(self, text="Aproxime o Chachá...", font=("Arial", 30), fg="#F400A1")
        self.status_label = tk.Label(self, text="Aproxime o Chachá...", font=("Arial", 30), fg="#F400A1", anchor="w", wraplength=450)
        self.status_label.pack(pady=20)
        self.numero = ""
        self.bind("<Key>", self.key_pressed)

        self.funcionarios = {} # Var dados Apex
        self.atualizar_dados_apex() # Obtém os dados do Apex inicialmente

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
        self.after(3600000, self.atualizar_dados_apex) # Atualiza os dados a cada 1 hora -> está em milisegundos

    def enviar_dados_apex_oracle(self):
        with open("/home/pi/raspi/dados.txt", "a") as arquivo:
            horario = datetime.datetime.now().strftime(f'%d%m%y%H%M')
            print(horario)
            dados = f"{self.numero};{horario}\n"
            arquivo.write(dados)

        if self.verificar_conexao_internet():
            with open("/home/pi/raspi/dados.txt", "r") as arquivo:
                dados = arquivo.readlines()

            url = 'https://apex.pampili.com.br/ords/afvserver/ponto/pontoparanaiba'
            headers = {'Content-type': 'application/json'}
            linhas_mantidas = []

            for linha in dados:
                campos = linha.strip().split(";")
                payload = {
                    "cracha": campos[0],
                    "horario": campos[1]
                }
                json_payload = json.dumps(payload)

                response = requests.post(url, data=json_payload, headers=headers)

                if response.status_code == 200:
                    print(f"Dado {linha.strip()} enviado com sucesso para o sistema no Apex Oracle.")
                else:
                    print(f"Falha ao enviar dado {linha.strip()}. Status Code: {response.status_code}")
                    linhas_mantidas.append(linha)

            with open("/home/pi/raspi/dados.txt", "w") as arquivo:
                arquivo.writelines(linhas_mantidas)

            nome_funcionario = self.funcionarios.get(self.numero)

            if nome_funcionario:
                self.status_label.config(text=f"{nome_funcionario}")
            else:
                self.status_label.config(text="Crachá inexistente, ponto registrado!")

            self.after(1000, lambda: self.status_label.config(text="Aproxime o Chachá..."))
        
        else:
            nome_funcionario = self.funcionarios.get(self.numero)
            if nome_funcionario:
                self.status_label.config(text=f"{nome_funcionario}")
            else:
                self.status_label.config(text="Crachá inexistente, ponto registrado!")
            
            self.after(1000, lambda: self.status_label.config(text="Aproxime o Chachá..."))

        self.numero = ""

if __name__ == "__main__":
    app = PontoGUI()

    def verificar_conexao_e_enviar_dados():
        if app.verificar_conexao_internet():
            with open("/home/pi/raspi/dados.txt", "r") as arquivo:
                dados = arquivo.readlines()

            if dados:
                url = 'https://apex.pampili.com.br/ords/afvserver/ponto/pontoparanaiba'

                headers = {'Content-type': 'application/json'}
                linhas_mantidas = []

                for linha in dados:
                    campos = linha.strip().split(";")
                    payload = {
                        "cracha": campos[0],
                        "horario": campos[1]
                    }
                    json_payload = json.dumps(payload)

                    response = requests.post(url, data=json_payload, headers=headers)

                    if response.status_code == 200:
                        print(f"Dado {linha.strip()} enviado com sucesso para o sistema no Apex Oracle.")
                    else:
                        print(f"Falha ao enviar dado {linha.strip()}. Status Code: {response.status_code}")
                        linhas_mantidas.append(linha)

                with open("/home/pi/raspi/dados.txt", "w") as arquivo:
                    arquivo.writelines(linhas_mantidas)

        app.after(300000, verificar_conexao_e_enviar_dados)

    verificar_conexao_e_enviar_dados()
    app.mainloop()
