#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Diagnostic client for qdock-lan/1 replay or read-only serial observations."""
import argparse
import json
import os
import socket
import sys

MAX_LINE = 256 * 1024


def replay(host, port, token):
    with socket.create_connection((host, port), timeout=10) as sock:
        with sock.makefile('rb') as stream:
            def send(message):
                sock.sendall(json.dumps(message).encode('utf-8') + b'\n')

            def receive():
                line = stream.readline(MAX_LINE + 1)
                if not line or len(line) > MAX_LINE or not line.endswith(b'\n'):
                    raise ValueError('Conexión cerrada o mensaje incompleto/demasiado grande')
                message = json.loads(line)
                if not isinstance(message, dict):
                    raise ValueError('Mensaje JSON no válido')
                if message.get('message') == 'error':
                    raise ValueError('Servidor: ' + str(message.get('code')))
                return message

            send({'message': 'hello', 'protocol': 'qdock-lan/1', 'token': token})
            welcome = receive()
            if (welcome.get('message') != 'welcome'
                    or welcome.get('protocol') != 'qdock-lan/1'
                    or welcome.get('source') not in ('replay', 'serial')):
                raise ValueError('Protocolo o fuente incompatible')
            source = welcome['source']
            yield welcome
            send({'message': 'subscribe'})
            session = None
            sequence = 0
            while True:
                message = receive()
                kind = message.get('message')
                if kind == 'source_status' and session is None:
                    if not isinstance(message.get('session'), str) or not message['session']:
                        raise ValueError('Inicio de sesión no válido')
                    session = message['session']
                    if source == 'serial':
                        sequence = int(message['nextSequence']) - 1
                elif session is None or message.get('session') != session:
                    raise ValueError('Sesión incoherente')
                if kind == 'event':
                    sequence += 1
                    if (message.get('sequence') != str(sequence)
                            or message.get('quality') != 'candidate'
                            or message.get('source') != source):
                        raise ValueError('Discontinuidad o calidad inesperada')
                yield message
                if kind == 'source_status' and message.get('status') == 'error':
                    raise ValueError('Fuente serie: ' + str(message.get('error')))
                if kind == 'source_status' and message.get('status') == 'ended':
                    return


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    token = os.environ.get('QDOCK_LAN_TOKEN', '')
    if not token:
        parser.error('Define QDOCK_LAN_TOKEN en el entorno')
    try:
        for message in replay(args.host, args.port, token):
            print(json.dumps(message, ensure_ascii=True), flush=True)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
