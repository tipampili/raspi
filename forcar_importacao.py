import requests
import json
import datetime
import sqlite3
import time

def verificar_conexao_internet():
    try:
        requests.get("https://www.google.com")
        return True
    except:
        return False

def enviar_dados_para_apex():
    if verificar_conexao_internet():
        db_conn = sqlite3.connect("ponto_database.db")
        cursor = db_conn.cursor()
        # executando via crontab
        agora = datetime.datetime.now()
        intervalo = datetime.timedelta(minutes=10)
        hora = agora - intervalo
        hora_formatada = hora.strftime('%d%m%y%H%M')
        cursor.execute("SELECT * FROM ponto_data WHERE horario LIKE ?", (hora_formatada + '%',))
        #cursor.execute("SELECT * FROM ponto_data")
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
            time.sleep(1)

            response = requests.post(url, data=json_payload, headers=headers)

            if response.status_code == 200:
                print(f"Dado {linha} enviado com sucesso para o sistema no Apex Oracle.")

                #cursor.execute("DELETE FROM ponto_data WHERE cracha = ? AND horario = ?", (linha[0], linha[1]))
            else:
                print(f"Falha ao enviar dado {linha}. Status Code: {response.status_code}")
                linhas_mantidas.append(linha)

        db_conn.commit()
    else:
        print("Aguardando tempo mínimo ou sem conexão com a internet...")

if __name__ == "__main__":
    enviar_dados_para_apex()
