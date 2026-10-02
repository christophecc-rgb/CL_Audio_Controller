"""Embeddable dedicated UDP RX; caller supplies its existing local scene handler."""
import socket
import threading
import sys
from scene_backup_protocol import SceneBackupReceiver, unicast_ipv4


class SceneBackupUDPReceiver:
    def __init__(self,*,source_ip,show,session,secret,allowed_source,on_scene,port=12042,source_interface=None):
        self.bind_ip=unicast_ipv4(source_ip)
        self.source_interface=source_interface
        self.port=int(port)
        if not 1<=self.port<=65535:
            raise ValueError('Port invalide')
        self.protocol=SceneBackupReceiver(show,session,secret,allowed_source=allowed_source)
        self.on_scene=on_scene
        self.stop_event=threading.Event(); self.thread=None; self.sock=None
        self.accepted=self.rejected=self.handler_errors=0

    def start(self):
        if self.thread and self.thread.is_alive(): return
        if self.stop_event.is_set(): raise RuntimeError('Récepteur fermé')
        self.sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        try:
            if self.source_interface:
                index=socket.if_nametoindex(self.source_interface)
                if sys.platform=='darwin':
                    self.sock.setsockopt(socket.IPPROTO_IP,getattr(socket,'IP_BOUND_IF',25),index)
                elif sys.platform.startswith('linux'):
                    self.sock.setsockopt(socket.SOL_SOCKET,getattr(socket,'SO_BINDTODEVICE',25),self.source_interface.encode()+b'\0')
                else:
                    raise OSError('Liaison interface non supportée')
            self.sock.bind((self.bind_ip,self.port)); self.sock.settimeout(.1)
        except Exception:
            self.sock.close(); self.sock=None; raise
        self.thread=threading.Thread(target=self._run,name='CL Scene Backup RX',daemon=True); self.thread.start()

    def _run(self):
        while not self.stop_event.is_set():
            try: raw,source=self.sock.recvfrom(2049)
            except socket.timeout: continue
            except OSError: break
            try:
                scene,reply=self.protocol.handle(raw,source[0])
                if reply: self.sock.sendto(reply,source)
            except (ValueError,TypeError,KeyError,UnicodeError,OSError):
                self.rejected+=1; continue
            if scene is not None and not self.stop_event.is_set():
                self.accepted+=1
                try: self.on_scene(scene)
                except Exception: self.handler_errors+=1

    def close(self):
        self.stop_event.set()
        if self.thread and self.thread is not threading.current_thread(): self.thread.join(timeout=1)
        if self.sock: self.sock.close()
        return not self.thread or not self.thread.is_alive()

    def snapshot(self):
        return {'state':self.protocol.status(),'source_ip':self.bind_ip,'source_interface':self.source_interface,'port':self.port,'accepted':self.accepted,
                'rejected':self.rejected,'handler_errors':self.handler_errors,'running':bool(self.thread and self.thread.is_alive())}
