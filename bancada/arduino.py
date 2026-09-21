"""
arduino.py
==========
Comunicacao serial (UART sobre USB) entre o script da bancada e a placa.

PROTOCOLO (uma linha JSON por mensagem, terminada em \\n, 9600 baud):

  PC -> Arduino
    {"cmd":"PING"}
    {"cmd":"STATUS","estado":"OK|ATENCAO|CRITICO|QUARENTENA","risco":0.82,"serial":"BR123"}
    {"cmd":"RESET"}

  Arduino -> PC
    {"ok":true,"bancada":"URE-01-B1","fw":"1.0.0"}
    {"ok":true,"led":"vermelho","bancada":"URE-01-B1"}

HONESTIDADE TECNICA (importante para a defesa do PI):
Isto NAO e autenticacao criptografica. O Arduino confirma que existe uma
bancada fisica plugada na USB e sinaliza o resultado nos LEDs. Um operador
com acesso ao codigo consegue simular a resposta ou ignorar a placa.
O papel real do Arduino aqui e INTERLOCK OPERACIONAL e SINALIZACAO FISICA,
nao seguranca. Chame assim no relatorio.
"""

import json
import time

import serial
import serial.tools.list_ports

BAUD = 9600
TIMEOUT = 3.0

# Identificacao por VID/PID do conversor USB-serial.
# Mais confiavel que olhar a descricao da porta, que muda conforme o driver,
# o idioma do Windows e o fabricante do clone.
#
#   0x2341, 0x2A03, 0x2A01 - Arduino oficial (UNO, Mega, Leonardo)
#   0x1A86                 - WCH CH340 / CH341 (clones chineses)
#   0x10C4                 - Silicon Labs CP2102 / CP210x
#   0x0403                 - FTDI FT232
#   0x067B                 - Prolific PL2303
VIDS_CONHECIDOS = {
    0x2341: "Arduino",
    0x2A03: "Arduino (Genuino)",
    0x2A01: "Arduino",
    0x1A86: "CH340/CH341",
    0x10C4: "CP210x",
    0x0403: "FTDI",
    0x067B: "PL2303",
}

# Fallback por descricao, para placas cujo VID nao esta na lista.
TERMOS_DESCRICAO = (
    "arduino", "ch340", "ch341", "cp210", "cp2102", "silicon labs",
    "usb-serial", "usb serial", "wch", "ftdi", "ft232", "pl2303",
    "prolific", "usb2.0-serial", "blackboard", "usb-enhanced-serial",
)


class BancadaNaoEncontrada(Exception):
    pass


def listar_portas():
    """Lista as portas seriais visiveis, com VID/PID, para diagnostico."""
    saida = []
    for p in serial.tools.list_ports.comports():
        vid = f"{p.vid:04X}" if p.vid else "----"
        pid = f"{p.pid:04X}" if p.pid else "----"
        chip = VIDS_CONHECIDOS.get(p.vid, "")
        saida.append((p.device, p.description, f"VID:{vid} PID:{pid}", chip))
    return saida


def detectar_porta(preferir=None):
    """
    Procura automaticamente a porta da placa.

    preferir: string opcional para desempate quando ha mais de uma placa
              (ex: "CP210" ou "COM5").
    """
    candidatos = []

    for p in serial.tools.list_ports.comports():
        pontuacao = 0

        # VID conhecido e o sinal mais forte
        if p.vid in VIDS_CONHECIDOS:
            pontuacao += 10
            # Arduino oficial tem prioridade sobre conversor generico
            if p.vid in (0x2341, 0x2A03, 0x2A01):
                pontuacao += 5

        texto = f"{p.description} {p.manufacturer or ''} {p.product or ''}".lower()
        if any(t in texto for t in TERMOS_DESCRICAO):
            pontuacao += 3

        # Bluetooth virtual aparece como porta serial e nunca e a placa
        if "bluetooth" in texto:
            pontuacao = -1

        if preferir and preferir.lower() in f"{p.device} {texto}".lower():
            pontuacao += 20

        if pontuacao > 0:
            candidatos.append((pontuacao, p.device, p.description))

    if not candidatos:
        linhas = "\n".join(
            f"    {dev:8s}  {desc}  [{ids}] {chip}"
            for dev, desc, ids, chip in listar_portas())
        raise BancadaNaoEncontrada(
            "Nenhuma placa encontrada.\n"
            f"  Portas visiveis:\n{linhas or '    (nenhuma)'}\n"
            "  Verifique:\n"
            "    - o cabo USB transmite dados? (existe cabo so de carga)\n"
            "    - o driver do conversor esta instalado?\n"
            "        CH340: driver WCH | CP2102: driver Silicon Labs\n"
            "    - o Serial Monitor da Arduino IDE esta fechado?\n"
            "      (ele trava a porta e impede outro programa de abrir)")

    candidatos.sort(reverse=True)
    return candidatos[0][1]


class Bancada:
    """Conexao com a placa. Use como context manager."""

    def __init__(self, porta=None, baud=BAUD, timeout=TIMEOUT):
        self.porta = porta or detectar_porta()
        self.baud = baud
        self.timeout = timeout
        self.ser = None
        self.id_bancada = None
        self.firmware = None

    def __enter__(self):
        self.conectar()
        return self

    def __exit__(self, *exc):
        self.fechar()

    def conectar(self):
        self.ser = serial.Serial(self.porta, self.baud, timeout=self.timeout)
        # A placa reinicia quando a porta serial abre; esperar o boot.
        # Placas com CP2102 costumam demorar um pouco mais que as com CH340.
        time.sleep(2.5)
        self.ser.reset_input_buffer()

        resp = self.enviar({"cmd": "PING"}, tentativas=3)
        if not resp or not resp.get("ok"):
            raise BancadaNaoEncontrada(
                f"A porta {self.porta} abriu, mas nao houve resposta ao PING.\n"
                "  O firmware bancada_token.ino esta gravado na placa?\n"
                "  A velocidade da serial no firmware e 9600?")

        self.id_bancada = resp.get("bancada")
        self.firmware = resp.get("fw")
        return self

    def enviar(self, payload, tentativas=2):
        """Manda um dict como linha JSON e devolve a resposta como dict."""
        linha = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
        for _ in range(tentativas):
            self.ser.reset_input_buffer()
            self.ser.write(linha)
            self.ser.flush()
            bruto = self.ser.readline().decode(errors="ignore").strip()
            if not bruto:
                continue
            try:
                return json.loads(bruto)
            except json.JSONDecodeError:
                continue  # provavelmente ruido do boot; tenta de novo
        return None

    def sinalizar(self, estado, risco=None, serial_maquina=None):
        """
        estado: 'OK' | 'ATENCAO' | 'CRITICO' | 'QUARENTENA'
        Acende o LED correspondente na bancada.
        """
        return self.enviar({
            "cmd": "STATUS",
            "estado": estado,
            "risco": round(float(risco), 3) if risco is not None else None,
            "serial": serial_maquina,
        })

    def resetar(self):
        return self.enviar({"cmd": "RESET"})

    def fechar(self):
        if self.ser and self.ser.is_open:
            try:
                self.resetar()
            except Exception:
                pass
            self.ser.close()


if __name__ == "__main__":
    print("Portas seriais visiveis:\n")
    for dev, desc, ids, chip in listar_portas():
        marca = f"  <- {chip}" if chip else ""
        print(f"  {dev:8s}  {desc}")
        print(f"            {ids}{marca}")
    print()

    try:
        with Bancada() as b:
            print(f"Conectado em {b.porta}")
            print(f"Bancada  : {b.id_bancada}")
            print(f"Firmware : {b.firmware}\n")

            for estado in ["OK", "ATENCAO", "CRITICO", "QUARENTENA"]:
                print(f"  testando LED -> {estado}")
                print("   ", b.sinalizar(estado, risco=0.5,
                                         serial_maquina="TESTE01"))
                time.sleep(1.5)

            print("\nTeste concluido.")
    except BancadaNaoEncontrada as e:
        print(f"ERRO: {e}")
