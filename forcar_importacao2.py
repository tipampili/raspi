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
        hora = datetime.datetime.now() - datetime.timedelta(hours=1)
        hora_formatada = hora.strftime('%d%m%y%H')

        db_conn = sqlite3.connect("ponto_database.db")
        cursor = db_conn.cursor()
        cursor.execute("SELECT * FROM ponto_data WHERE horario LIKE ?", (hora_formatada + '%',))
        dados = cursor.fetchall()

        if len(dados) > 0:
            colunas = [desc[0] for desc in cursor.description]
            dados_formatados = [dict(zip(colunas, linha)) for linha in dados]
            json_data = json.dumps(dados_formatados)
            json_string = json.dumps({"batidas": json_data})

            url = 'https://apex.pampili.com.br/ords/afvserver/ponto/ponto-paranaiba2'
            headers = {'Content-type': 'application/json'}

            response = requests.post(url, data=json_string, headers=headers)

            if response.status_code == 200:
                print(f"Dados enviados com sucesso para o sistema no Apex Oracle.")
            else:
                print(f"Falha ao enviar dados. Status Code: {response.status_code}")

            db_conn.commit()
        else:
            print("Nenhuma batida a ser enviada.")
    else:
        print("Aguardando tempo mínimo ou sem conexão com a internet...")

if __name__ == "__main__":
    enviar_dados_para_apex()