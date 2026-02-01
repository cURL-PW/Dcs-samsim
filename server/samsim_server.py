#!/usr/bin/env python3
"""
SAMSIM Server

This server bridges DCS World and the web browser interface.
- Receives UDP data from DCS Export.lua
- Sends commands to DCS via UDP
- Provides WebSocket connection for browser
- Serves static web files via HTTP
"""

import asyncio
import json
import logging
import socket
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

try:
    import websockets
    from websockets.server import serve as ws_serve
except ImportError:
    print("Please install websockets: pip install websockets")
    exit(1)

try:
    from aiohttp import web
except ImportError:
    print("Please install aiohttp: pip install aiohttp")
    exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('SAMSIM')


@dataclass
class ServerConfig:
    """Server configuration"""
    # DCS communication
    dcs_recv_port: int = 7777      # Receive status from DCS
    dcs_send_port: int = 7778      # Send commands to DCS
    dcs_host: str = "127.0.0.1"

    # Web server
    http_port: int = 8080
    websocket_port: int = 8081
    static_dir: str = "static"

    # Broadcast interval for websocket clients
    broadcast_interval: float = 0.1  # 100ms


@dataclass
class SAMSiteState:
    """State of a single SA-2 site"""
    site_id: str
    system_state: int = 0
    radar_mode: int = 0
    antenna_az: float = 0.0
    antenna_el: float = 5.0
    targets: list = field(default_factory=list)
    tracked_target: Optional[dict] = None
    track_quality: int = 0
    missiles_ready: int = 6
    missiles_in_flight: int = 0
    engagement_auth: bool = False
    auto_engage: bool = False


class SAMSIMServer:
    """Main SAMSIM server class"""

    def __init__(self, config: ServerConfig):
        self.config = config
        self.running = False

        # DCS state
        self.dcs_connected = False
        self.last_dcs_update = 0
        self.mission_time = 0
        self.paused = False

        # SA-2 sites state
        self.sites: dict[str, SAMSiteState] = {}

        # World objects (aircraft, etc.)
        self.world_objects = []

        # WebSocket clients
        self.ws_clients: set = set()

        # UDP sockets
        self.udp_recv_socket: Optional[socket.socket] = None
        self.udp_send_socket: Optional[socket.socket] = None

        # Locks for thread safety
        self.state_lock = threading.Lock()

    async def start(self):
        """Start the server"""
        logger.info("Starting SAMSIM Server...")
        self.running = True

        # Initialize UDP sockets
        self._init_udp_sockets()

        # Start all services
        await asyncio.gather(
            self._run_udp_receiver(),
            self._run_websocket_server(),
            self._run_http_server(),
            self._broadcast_loop(),
        )

    def _init_udp_sockets(self):
        """Initialize UDP sockets for DCS communication"""
        # Receive socket
        self.udp_recv_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.udp_recv_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.udp_recv_socket.bind(("0.0.0.0", self.config.dcs_recv_port))
        self.udp_recv_socket.setblocking(False)

        # Send socket
        self.udp_send_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

        logger.info(f"UDP receiver bound to port {self.config.dcs_recv_port}")
        logger.info(f"UDP sender ready to port {self.config.dcs_send_port}")

    async def _run_udp_receiver(self):
        """Receive data from DCS"""
        logger.info("UDP receiver started")
        loop = asyncio.get_event_loop()

        while self.running:
            try:
                # Use asyncio to handle the non-blocking socket
                data = await loop.run_in_executor(
                    None, self._recv_udp_data
                )
                if data:
                    self._process_dcs_data(data)
            except Exception as e:
                if self.running:
                    logger.error(f"UDP receive error: {e}")
            await asyncio.sleep(0.01)

    def _recv_udp_data(self) -> Optional[bytes]:
        """Non-blocking UDP receive"""
        try:
            data, addr = self.udp_recv_socket.recvfrom(65535)
            return data
        except BlockingIOError:
            return None
        except Exception:
            return None

    def _process_dcs_data(self, data: bytes):
        """Process data received from DCS"""
        try:
            message = json.loads(data.decode('utf-8'))
            msg_type = message.get('type', '')

            with self.state_lock:
                if msg_type == 'init':
                    self.dcs_connected = True
                    logger.info("DCS connected")

                elif msg_type == 'shutdown':
                    self.dcs_connected = False
                    logger.info("DCS disconnected")

                elif msg_type == 'status':
                    self.dcs_connected = True
                    self.mission_time = message.get('time', 0)
                    self.paused = message.get('paused', False)

                    # Update world objects
                    self.world_objects = message.get('worldObjects', [])

                    # Update site states
                    sites_data = message.get('sites', {})
                    for site_id, site_data in sites_data.items():
                        if site_id not in self.sites:
                            self.sites[site_id] = SAMSiteState(site_id=site_id)

                        site = self.sites[site_id]
                        site.system_state = site_data.get('systemState', 0)
                        site.radar_mode = site_data.get('radarMode', 0)
                        site.antenna_az = site_data.get('antennaAz', 0)
                        site.antenna_el = site_data.get('antennaEl', 5)
                        site.targets = site_data.get('targets', [])
                        site.tracked_target = site_data.get('tracked')
                        site.track_quality = site_data.get('trackQuality', 0)
                        site.missiles_ready = site_data.get('missilesReady', 6)
                        site.missiles_in_flight = site_data.get('missilesInFlight', 0)
                        site.engagement_auth = site_data.get('engAuth', False)
                        site.auto_engage = site_data.get('autoEng', False)

                elif msg_type == 'response':
                    # Response from command - forward to WebSocket clients
                    pass

        except json.JSONDecodeError as e:
            logger.warning(f"Invalid JSON from DCS: {e}")
        except Exception as e:
            logger.error(f"Error processing DCS data: {e}")

    def send_to_dcs(self, command: dict):
        """Send command to DCS"""
        try:
            data = json.dumps(command).encode('utf-8')
            self.udp_send_socket.sendto(
                data,
                (self.config.dcs_host, self.config.dcs_send_port)
            )
            logger.debug(f"Sent to DCS: {command}")
        except Exception as e:
            logger.error(f"Failed to send to DCS: {e}")

    async def _run_websocket_server(self):
        """Run WebSocket server for browser clients"""
        async def handler(websocket):
            # Register client
            self.ws_clients.add(websocket)
            client_addr = websocket.remote_address
            logger.info(f"WebSocket client connected: {client_addr}")

            try:
                async for message in websocket:
                    await self._handle_ws_message(websocket, message)
            except websockets.exceptions.ConnectionClosed:
                pass
            finally:
                self.ws_clients.discard(websocket)
                logger.info(f"WebSocket client disconnected: {client_addr}")

        logger.info(f"WebSocket server starting on port {self.config.websocket_port}")
        async with ws_serve(handler, "0.0.0.0", self.config.websocket_port):
            await asyncio.Future()  # Run forever

    async def _handle_ws_message(self, websocket, message: str):
        """Handle message from WebSocket client"""
        try:
            data = json.loads(message)
            cmd_type = data.get('type', '')

            if cmd_type == 'command':
                # Forward command to DCS
                command = data.get('command', {})
                self.send_to_dcs(command)

                # Send acknowledgment
                await websocket.send(json.dumps({
                    'type': 'ack',
                    'command': command.get('cmd'),
                }))

            elif cmd_type == 'init_site':
                # Initialize a new SA-2 site
                site_id = data.get('siteId')
                group_name = data.get('groupName')

                command = {
                    'cmd': 'init_site',
                    'siteId': site_id,
                    'params': {'groupName': group_name}
                }
                self.send_to_dcs(command)

                # Create local state
                with self.state_lock:
                    if site_id not in self.sites:
                        self.sites[site_id] = SAMSiteState(site_id=site_id)

            elif cmd_type == 'get_state':
                # Send current state to client
                await self._send_state_to_client(websocket)

        except json.JSONDecodeError:
            logger.warning(f"Invalid JSON from WebSocket: {message}")
        except Exception as e:
            logger.error(f"Error handling WebSocket message: {e}")

    async def _send_state_to_client(self, websocket):
        """Send current state to a WebSocket client"""
        with self.state_lock:
            state = {
                'type': 'state',
                'dcsConnected': self.dcs_connected,
                'missionTime': self.mission_time,
                'paused': self.paused,
                'sites': {
                    site_id: {
                        'siteId': site.site_id,
                        'systemState': site.system_state,
                        'radarMode': site.radar_mode,
                        'antennaAz': site.antenna_az,
                        'antennaEl': site.antenna_el,
                        'targets': site.targets,
                        'tracked': site.tracked_target,
                        'trackQuality': site.track_quality,
                        'missilesReady': site.missiles_ready,
                        'missilesInFlight': site.missiles_in_flight,
                        'engAuth': site.engagement_auth,
                        'autoEng': site.auto_engage,
                    }
                    for site_id, site in self.sites.items()
                },
                'worldObjects': self.world_objects,
            }

        try:
            await websocket.send(json.dumps(state))
        except Exception as e:
            logger.error(f"Failed to send state to client: {e}")

    async def _broadcast_loop(self):
        """Broadcast state updates to all WebSocket clients"""
        while self.running:
            if self.ws_clients:
                with self.state_lock:
                    state = {
                        'type': 'update',
                        'dcsConnected': self.dcs_connected,
                        'missionTime': self.mission_time,
                        'paused': self.paused,
                        'sites': {
                            site_id: {
                                'siteId': site.site_id,
                                'systemState': site.system_state,
                                'radarMode': site.radar_mode,
                                'antennaAz': site.antenna_az,
                                'antennaEl': site.antenna_el,
                                'targets': site.targets,
                                'tracked': site.tracked_target,
                                'trackQuality': site.track_quality,
                                'missilesReady': site.missiles_ready,
                                'missilesInFlight': site.missiles_in_flight,
                                'engAuth': site.engagement_auth,
                                'autoEng': site.auto_engage,
                            }
                            for site_id, site in self.sites.items()
                        },
                        'worldObjects': self.world_objects,
                    }

                message = json.dumps(state)

                # Broadcast to all clients
                dead_clients = set()
                for client in self.ws_clients:
                    try:
                        await client.send(message)
                    except Exception:
                        dead_clients.add(client)

                # Remove dead clients
                self.ws_clients -= dead_clients

            await asyncio.sleep(self.config.broadcast_interval)

    async def _run_http_server(self):
        """Run HTTP server for static files"""
        app = web.Application()

        # Static files
        static_path = Path(__file__).parent / self.config.static_dir
        if static_path.exists():
            app.router.add_static('/', static_path, name='static')

        # Add index redirect
        async def index_handler(request):
            raise web.HTTPFound('/index.html')

        app.router.add_get('/', index_handler)

        # API endpoints
        app.router.add_get('/api/status', self._api_status)
        app.router.add_post('/api/command', self._api_command)

        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, "0.0.0.0", self.config.http_port)
        await site.start()

        logger.info(f"HTTP server started on http://localhost:{self.config.http_port}")
        await asyncio.Future()  # Run forever

    async def _api_status(self, request):
        """API endpoint: Get current status"""
        with self.state_lock:
            status = {
                'dcsConnected': self.dcs_connected,
                'missionTime': self.mission_time,
                'paused': self.paused,
                'sites': list(self.sites.keys()),
            }
        return web.json_response(status)

    async def _api_command(self, request):
        """API endpoint: Send command to DCS"""
        try:
            data = await request.json()
            self.send_to_dcs(data)
            return web.json_response({'success': True})
        except Exception as e:
            return web.json_response({'success': False, 'error': str(e)})


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description='SAMSIM Server')
    parser.add_argument('--http-port', type=int, default=8080, help='HTTP server port')
    parser.add_argument('--ws-port', type=int, default=8081, help='WebSocket server port')
    parser.add_argument('--dcs-recv-port', type=int, default=7777, help='DCS receive port')
    parser.add_argument('--dcs-send-port', type=int, default=7778, help='DCS send port')
    parser.add_argument('--debug', action='store_true', help='Enable debug logging')

    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    config = ServerConfig(
        http_port=args.http_port,
        websocket_port=args.ws_port,
        dcs_recv_port=args.dcs_recv_port,
        dcs_send_port=args.dcs_send_port,
    )

    server = SAMSIMServer(config)

    print(f"""
    ╔═══════════════════════════════════════════════════════════╗
    ║                    SAMSIM Server                          ║
    ╠═══════════════════════════════════════════════════════════╣
    ║  HTTP Server:      http://localhost:{config.http_port:<5}               ║
    ║  WebSocket Server: ws://localhost:{config.websocket_port:<5}                 ║
    ║  DCS Receive Port: {config.dcs_recv_port:<5}                              ║
    ║  DCS Send Port:    {config.dcs_send_port:<5}                              ║
    ╠═══════════════════════════════════════════════════════════╣
    ║  Open http://localhost:{config.http_port:<5} in your browser           ║
    ║  Press Ctrl+C to stop                                     ║
    ╚═══════════════════════════════════════════════════════════╝
    """)

    try:
        asyncio.run(server.start())
    except KeyboardInterrupt:
        logger.info("Shutting down...")


if __name__ == '__main__':
    main()
