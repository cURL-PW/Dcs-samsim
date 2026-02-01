/**
 * SAMSIM Client JavaScript
 * SA-2 (S-75) SAMSim Controller for DCS World
 */

class SAMSIMClient {
    constructor() {
        // WebSocket connection
        this.ws = null;
        this.wsConnected = false;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 10;
        this.reconnectDelay = 2000;

        // State
        this.dcsConnected = false;
        this.missionTime = 0;
        this.paused = false;
        this.sites = {};
        this.worldObjects = [];
        this.activeSiteId = null;
        this.selectedTargetId = null;

        // Radar display settings
        this.radarRange = 80000; // 80 km
        this.radarCenterX = 250;
        this.radarCenterY = 250;
        this.radarRadius = 240;

        // Canvas contexts
        this.radarCtx = null;
        this.elevationCtx = null;

        // Animation
        this.sweepAngle = 0;
        this.lastFrameTime = 0;

        // Initialize
        this.init();
    }

    init() {
        // Get canvas contexts
        const radarCanvas = document.getElementById('radarScope');
        const elevationCanvas = document.getElementById('elevationScope');

        if (radarCanvas) {
            this.radarCtx = radarCanvas.getContext('2d');
        }
        if (elevationCanvas) {
            this.elevationCtx = elevationCanvas.getContext('2d');
        }

        // Bind event listeners
        this.bindEvents();

        // Generate missile indicators
        this.generateMissileIndicators();

        // Connect to WebSocket
        this.connect();

        // Start animation loop
        this.animate();
    }

    bindEvents() {
        // Radar range selector
        document.getElementById('radarRange')?.addEventListener('change', (e) => {
            this.radarRange = parseInt(e.target.value) * 1000;
        });

        // Antenna controls
        document.getElementById('antennaAz')?.addEventListener('input', (e) => {
            const value = parseInt(e.target.value);
            document.getElementById('antennaAzValue').textContent = value + '\u00b0';
            this.sendCommand('command_antenna', { azimuth: value, elevation: this.getAntennaEl() });
        });

        document.getElementById('antennaEl')?.addEventListener('input', (e) => {
            const value = parseInt(e.target.value);
            document.getElementById('antennaElValue').textContent = value + '\u00b0';
            this.sendCommand('command_antenna', { azimuth: this.getAntennaAz(), elevation: value });
        });

        // System control buttons
        document.getElementById('btnPowerOn')?.addEventListener('click', () => {
            this.sendCommand('set_system_state', { state: 2 }); // READY
        });

        document.getElementById('btnStandby')?.addEventListener('click', () => {
            this.sendCommand('set_radar_mode', { mode: 0 }); // STANDBY
        });

        document.getElementById('btnSearch')?.addEventListener('click', () => {
            this.sendCommand('set_radar_mode', { mode: 1 }); // SEARCH
        });

        // Engagement controls
        document.getElementById('btnDesignate')?.addEventListener('click', () => {
            if (this.selectedTargetId) {
                this.sendCommand('designate_target', { targetId: this.selectedTargetId });
            }
        });

        document.getElementById('btnDropTrack')?.addEventListener('click', () => {
            this.sendCommand('drop_track', {});
        });

        document.getElementById('btnLaunch')?.addEventListener('click', () => {
            if (confirm('Confirm missile launch?')) {
                this.sendCommand('launch_missile', {});
            }
        });

        // Toggle switches
        document.getElementById('engAuthToggle')?.addEventListener('change', (e) => {
            this.sendCommand('set_eng_auth', { authorized: e.target.checked });
        });

        document.getElementById('autoEngToggle')?.addEventListener('change', (e) => {
            this.sendCommand('set_auto_engage', { autoEngage: e.target.checked });
        });

        // Site selector
        document.getElementById('siteSelect')?.addEventListener('change', (e) => {
            this.activeSiteId = e.target.value || null;
        });

        // Init site modal
        document.getElementById('initSiteBtn')?.addEventListener('click', () => {
            document.getElementById('initSiteModal').classList.add('active');
        });

        document.getElementById('cancelInitSite')?.addEventListener('click', () => {
            document.getElementById('initSiteModal').classList.remove('active');
        });

        document.getElementById('confirmInitSite')?.addEventListener('click', () => {
            const siteId = document.getElementById('newSiteId').value;
            const groupName = document.getElementById('groupName').value;

            if (siteId && groupName) {
                this.initSite(siteId, groupName);
                document.getElementById('initSiteModal').classList.remove('active');
            }
        });

        // Click on radar to designate target
        document.getElementById('radarScope')?.addEventListener('click', (e) => {
            this.handleRadarClick(e);
        });
    }

    getAntennaAz() {
        return parseInt(document.getElementById('antennaAz')?.value || 0);
    }

    getAntennaEl() {
        return parseInt(document.getElementById('antennaEl')?.value || 5);
    }

    generateMissileIndicators() {
        const container = document.getElementById('missileIndicators');
        if (!container) return;

        container.innerHTML = '';
        for (let i = 0; i < 6; i++) {
            const indicator = document.createElement('div');
            indicator.className = 'missile-indicator';
            indicator.id = `missile-${i}`;
            container.appendChild(indicator);
        }
    }

    connect() {
        const wsPort = 8081;
        const wsUrl = `ws://${window.location.hostname}:${wsPort}`;

        console.log('Connecting to WebSocket:', wsUrl);

        try {
            this.ws = new WebSocket(wsUrl);

            this.ws.onopen = () => {
                console.log('WebSocket connected');
                this.wsConnected = true;
                this.reconnectAttempts = 0;
                this.updateConnectionStatus();

                // Request current state
                this.ws.send(JSON.stringify({ type: 'get_state' }));
            };

            this.ws.onclose = () => {
                console.log('WebSocket disconnected');
                this.wsConnected = false;
                this.updateConnectionStatus();
                this.scheduleReconnect();
            };

            this.ws.onerror = (error) => {
                console.error('WebSocket error:', error);
            };

            this.ws.onmessage = (event) => {
                this.handleMessage(event.data);
            };
        } catch (error) {
            console.error('Failed to connect:', error);
            this.scheduleReconnect();
        }
    }

    scheduleReconnect() {
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
            this.reconnectAttempts++;
            console.log(`Reconnecting in ${this.reconnectDelay}ms (attempt ${this.reconnectAttempts})`);
            setTimeout(() => this.connect(), this.reconnectDelay);
        }
    }

    handleMessage(data) {
        try {
            const message = JSON.parse(data);

            switch (message.type) {
                case 'state':
                case 'update':
                    this.updateState(message);
                    break;
                case 'ack':
                    console.log('Command acknowledged:', message.command);
                    break;
                default:
                    console.log('Unknown message type:', message.type);
            }
        } catch (error) {
            console.error('Failed to parse message:', error);
        }
    }

    updateState(state) {
        this.dcsConnected = state.dcsConnected;
        this.missionTime = state.missionTime || 0;
        this.paused = state.paused;
        this.sites = state.sites || {};
        this.worldObjects = state.worldObjects || [];

        this.updateUI();
    }

    updateUI() {
        // Connection status
        this.updateConnectionStatus();

        // Mission time
        const timeStr = this.formatTime(this.missionTime);
        document.getElementById('missionTime').textContent = timeStr;

        // Update site selector
        this.updateSiteSelector();

        // Update active site display
        if (this.activeSiteId && this.sites[this.activeSiteId]) {
            this.updateSiteDisplay(this.sites[this.activeSiteId]);
        }

        // Last update time
        document.getElementById('lastUpdate').textContent = new Date().toLocaleTimeString();
    }

    updateConnectionStatus() {
        const statusDot = document.querySelector('.connection-status .status-dot');
        const statusText = document.querySelector('.connection-status .status-text');
        const wsStatus = document.getElementById('wsStatus');
        const dcsStatus = document.getElementById('dcsStatus');

        if (this.wsConnected && this.dcsConnected) {
            statusDot?.classList.remove('disconnected');
            statusDot?.classList.add('connected');
            if (statusText) statusText.textContent = 'Connected';
        } else {
            statusDot?.classList.remove('connected');
            statusDot?.classList.add('disconnected');
            if (statusText) statusText.textContent = 'Disconnected';
        }

        if (wsStatus) wsStatus.textContent = this.wsConnected ? 'Connected' : 'Disconnected';
        if (dcsStatus) dcsStatus.textContent = this.dcsConnected ? 'Connected' : 'Not Connected';
    }

    updateSiteSelector() {
        const selector = document.getElementById('siteSelect');
        if (!selector) return;

        const currentValue = selector.value;
        const siteIds = Object.keys(this.sites);

        // Clear and rebuild options
        selector.innerHTML = '<option value="">-- Select Site --</option>';
        siteIds.forEach(siteId => {
            const option = document.createElement('option');
            option.value = siteId;
            option.textContent = siteId;
            selector.appendChild(option);
        });

        // Restore selection
        if (currentValue && siteIds.includes(currentValue)) {
            selector.value = currentValue;
        } else if (siteIds.length > 0 && !this.activeSiteId) {
            selector.value = siteIds[0];
            this.activeSiteId = siteIds[0];
        }
    }

    updateSiteDisplay(site) {
        // Radar mode display
        const modeNames = ['STANDBY', 'SEARCH', 'TRACK', 'GUIDE'];
        const radarModeDisplay = document.getElementById('radarModeDisplay');
        if (radarModeDisplay) {
            radarModeDisplay.textContent = modeNames[site.radarMode] || 'UNKNOWN';
        }

        // Indicators
        const indPower = document.getElementById('indPower');
        const indRadar = document.getElementById('indRadar');
        const indTrack = document.getElementById('indTrack');
        const indGuide = document.getElementById('indGuide');

        indPower?.classList.toggle('active', site.systemState >= 2);
        indRadar?.classList.toggle('active', site.radarMode >= 1);
        indTrack?.classList.toggle('active', site.radarMode >= 2);
        indGuide?.classList.toggle('active', site.radarMode >= 3);
        indGuide?.classList.toggle('danger', site.radarMode >= 3);

        // Target list
        this.updateTargetList(site.targets);

        // Tracked target
        if (site.tracked) {
            document.getElementById('tgtId').textContent = site.tracked.id;
            document.getElementById('tgtRange').textContent = (site.tracked.range / 1000).toFixed(1) + ' km';
            document.getElementById('tgtAzimuth').textContent = site.tracked.azimuth.toFixed(1) + '\u00b0';
            document.getElementById('tgtElevation').textContent = site.tracked.elevation.toFixed(1) + '\u00b0';
            document.getElementById('tgtAltitude').textContent = site.tracked.altitude + ' m';
        } else {
            document.getElementById('tgtId').textContent = '---';
            document.getElementById('tgtRange').textContent = '--- km';
            document.getElementById('tgtAzimuth').textContent = '---\u00b0';
            document.getElementById('tgtElevation').textContent = '---\u00b0';
            document.getElementById('tgtAltitude').textContent = '--- m';
        }

        // Track quality
        const quality = site.trackQuality || 0;
        document.getElementById('trackQuality').textContent = quality + '%';
        const qualityBar = document.getElementById('trackQualityBar');
        if (qualityBar) qualityBar.style.width = quality + '%';

        // Missiles
        document.getElementById('missilesReady').textContent = site.missilesReady;
        document.getElementById('missilesInFlight').textContent = site.missilesInFlight;

        // Update missile indicators
        for (let i = 0; i < 6; i++) {
            const indicator = document.getElementById(`missile-${i}`);
            if (indicator) {
                indicator.classList.toggle('empty', i >= site.missilesReady);
            }
        }

        // Toggle states
        document.getElementById('engAuthToggle').checked = site.engAuth;
        document.getElementById('autoEngToggle').checked = site.autoEng;
    }

    updateTargetList(targets) {
        const container = document.getElementById('targetList');
        if (!container) return;

        if (!targets || targets.length === 0) {
            container.innerHTML = '<div class="no-targets">No targets detected</div>';
            return;
        }

        container.innerHTML = '';
        targets.forEach(target => {
            const item = document.createElement('div');
            item.className = 'target-item';
            if (target.id === this.selectedTargetId) {
                item.classList.add('selected');
            }

            item.innerHTML = `
                <span class="target-id">${target.id}</span>
                <span class="target-info">${(target.range / 1000).toFixed(1)} km / ${target.azimuth.toFixed(0)}\u00b0</span>
            `;

            item.addEventListener('click', () => {
                this.selectedTargetId = target.id;
                document.querySelectorAll('.target-item').forEach(el => el.classList.remove('selected'));
                item.classList.add('selected');
            });

            container.appendChild(item);
        });
    }

    formatTime(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const s = Math.floor(seconds % 60);
        return `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
    }

    sendCommand(cmd, params) {
        if (!this.wsConnected || !this.activeSiteId) {
            console.warn('Cannot send command: not connected or no site selected');
            return;
        }

        const command = {
            type: 'command',
            command: {
                cmd: cmd,
                siteId: this.activeSiteId,
                params: params
            }
        };

        this.ws.send(JSON.stringify(command));
    }

    initSite(siteId, groupName) {
        if (!this.wsConnected) {
            console.warn('Cannot init site: not connected');
            return;
        }

        const message = {
            type: 'init_site',
            siteId: siteId,
            groupName: groupName
        };

        this.ws.send(JSON.stringify(message));
        this.activeSiteId = siteId;
    }

    handleRadarClick(event) {
        const rect = event.target.getBoundingClientRect();
        const x = event.clientX - rect.left - this.radarCenterX;
        const y = this.radarCenterY - (event.clientY - rect.top);

        // Calculate azimuth and range from click position
        const range = Math.sqrt(x * x + y * y) / this.radarRadius * this.radarRange;
        const azimuth = (Math.atan2(x, y) * 180 / Math.PI + 360) % 360;

        console.log(`Radar click: Range=${(range/1000).toFixed(1)}km, Az=${azimuth.toFixed(1)}\u00b0`);

        // Find closest target
        const site = this.sites[this.activeSiteId];
        if (site && site.targets) {
            let closestTarget = null;
            let closestDist = Infinity;

            site.targets.forEach(target => {
                const targetX = Math.sin(target.azimuth * Math.PI / 180) * target.range / this.radarRange * this.radarRadius;
                const targetY = Math.cos(target.azimuth * Math.PI / 180) * target.range / this.radarRange * this.radarRadius;
                const dist = Math.sqrt((x - targetX) ** 2 + (y - targetY) ** 2);

                if (dist < closestDist && dist < 30) {
                    closestDist = dist;
                    closestTarget = target;
                }
            });

            if (closestTarget) {
                this.selectedTargetId = closestTarget.id;
                this.updateTargetList(site.targets);
            }
        }
    }

    animate(timestamp) {
        const deltaTime = timestamp - this.lastFrameTime;
        this.lastFrameTime = timestamp;

        // Update sweep angle (6 degrees per second = 1 revolution per minute)
        this.sweepAngle = (this.sweepAngle + deltaTime * 0.006) % 360;

        // Draw radar
        this.drawRadar();

        // Draw elevation scope
        this.drawElevationScope();

        requestAnimationFrame((t) => this.animate(t));
    }

    drawRadar() {
        const ctx = this.radarCtx;
        if (!ctx) return;

        const centerX = this.radarCenterX;
        const centerY = this.radarCenterY;
        const radius = this.radarRadius;

        // Clear canvas
        ctx.fillStyle = '#001100';
        ctx.fillRect(0, 0, 500, 500);

        // Draw range rings
        ctx.strokeStyle = '#003300';
        ctx.lineWidth = 1;
        for (let i = 1; i <= 4; i++) {
            ctx.beginPath();
            ctx.arc(centerX, centerY, radius * i / 4, 0, Math.PI * 2);
            ctx.stroke();

            // Range labels
            const rangeKm = this.radarRange * i / 4 / 1000;
            ctx.fillStyle = '#006600';
            ctx.font = '10px monospace';
            ctx.fillText(rangeKm + 'km', centerX + 5, centerY - radius * i / 4 + 12);
        }

        // Draw azimuth lines
        for (let i = 0; i < 12; i++) {
            const angle = i * 30 * Math.PI / 180;
            ctx.beginPath();
            ctx.moveTo(centerX, centerY);
            ctx.lineTo(
                centerX + Math.sin(angle) * radius,
                centerY - Math.cos(angle) * radius
            );
            ctx.stroke();
        }

        // Draw cardinal directions
        ctx.fillStyle = '#00aa00';
        ctx.font = 'bold 12px monospace';
        ctx.fillText('N', centerX - 4, 15);
        ctx.fillText('S', centerX - 4, 495);
        ctx.fillText('E', 485, centerY + 4);
        ctx.fillText('W', 5, centerY + 4);

        // Draw sweep line (search mode)
        const site = this.sites[this.activeSiteId];
        if (site && site.radarMode === 1) {
            const sweepAngleRad = this.sweepAngle * Math.PI / 180;
            const gradient = ctx.createLinearGradient(
                centerX, centerY,
                centerX + Math.sin(sweepAngleRad) * radius,
                centerY - Math.cos(sweepAngleRad) * radius
            );
            gradient.addColorStop(0, 'rgba(0, 255, 0, 0.5)');
            gradient.addColorStop(1, 'rgba(0, 255, 0, 0)');

            ctx.strokeStyle = gradient;
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.moveTo(centerX, centerY);
            ctx.lineTo(
                centerX + Math.sin(sweepAngleRad) * radius,
                centerY - Math.cos(sweepAngleRad) * radius
            );
            ctx.stroke();
        }

        // Draw antenna direction (track/guide mode)
        if (site && site.radarMode >= 2) {
            const azRad = site.antennaAz * Math.PI / 180;
            ctx.strokeStyle = '#00ff00';
            ctx.lineWidth = 2;
            ctx.setLineDash([5, 5]);
            ctx.beginPath();
            ctx.moveTo(centerX, centerY);
            ctx.lineTo(
                centerX + Math.sin(azRad) * radius,
                centerY - Math.cos(azRad) * radius
            );
            ctx.stroke();
            ctx.setLineDash([]);
        }

        // Draw targets
        if (site && site.targets) {
            site.targets.forEach(target => {
                const rangeRatio = target.range / this.radarRange;
                if (rangeRatio > 1) return;

                const azRad = target.azimuth * Math.PI / 180;
                const x = centerX + Math.sin(azRad) * radius * rangeRatio;
                const y = centerY - Math.cos(azRad) * radius * rangeRatio;

                // Target blip
                const isTracked = site.tracked && site.tracked.id === target.id;
                const isSelected = target.id === this.selectedTargetId;

                if (isTracked) {
                    ctx.fillStyle = '#ff0000';
                    ctx.strokeStyle = '#ff0000';
                } else if (isSelected) {
                    ctx.fillStyle = '#ffff00';
                    ctx.strokeStyle = '#ffff00';
                } else {
                    ctx.fillStyle = '#00ff00';
                    ctx.strokeStyle = '#00ff00';
                }

                // Draw blip
                ctx.beginPath();
                ctx.arc(x, y, 5, 0, Math.PI * 2);
                ctx.fill();

                // Draw velocity vector
                if (target.closure) {
                    const velAngle = azRad + Math.PI; // Approximate
                    const velLength = Math.min(Math.abs(target.closure) / 10, 30);
                    ctx.beginPath();
                    ctx.moveTo(x, y);
                    ctx.lineTo(
                        x + Math.sin(velAngle) * velLength * Math.sign(target.closure),
                        y - Math.cos(velAngle) * velLength * Math.sign(target.closure)
                    );
                    ctx.stroke();
                }

                // Target ID label
                ctx.font = '10px monospace';
                ctx.fillText(target.id, x + 8, y - 5);
            });
        }

        // Draw engagement zone
        ctx.strokeStyle = 'rgba(255, 0, 0, 0.3)';
        ctx.lineWidth = 2;
        ctx.setLineDash([10, 5]);

        // Min engagement range (7km)
        const minEngRange = 7000 / this.radarRange * radius;
        ctx.beginPath();
        ctx.arc(centerX, centerY, minEngRange, 0, Math.PI * 2);
        ctx.stroke();

        // Max engagement range (45km)
        const maxEngRange = 45000 / this.radarRange * radius;
        ctx.beginPath();
        ctx.arc(centerX, centerY, maxEngRange, 0, Math.PI * 2);
        ctx.stroke();

        ctx.setLineDash([]);

        // Center dot
        ctx.fillStyle = '#00ff00';
        ctx.beginPath();
        ctx.arc(centerX, centerY, 3, 0, Math.PI * 2);
        ctx.fill();
    }

    drawElevationScope() {
        const ctx = this.elevationCtx;
        if (!ctx) return;

        const width = 200;
        const height = 300;

        // Clear
        ctx.fillStyle = '#001100';
        ctx.fillRect(0, 0, width, height);

        // Draw grid
        ctx.strokeStyle = '#003300';
        ctx.lineWidth = 1;

        // Horizontal lines (altitude)
        for (let i = 0; i <= 6; i++) {
            const y = height - (i * height / 6);
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(width, y);
            ctx.stroke();

            // Altitude labels
            ctx.fillStyle = '#006600';
            ctx.font = '9px monospace';
            ctx.fillText((i * 5) + 'km', 5, y - 3);
        }

        // Vertical lines (range)
        for (let i = 0; i <= 4; i++) {
            const x = i * width / 4;
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, height);
            ctx.stroke();
        }

        // Draw targets
        const site = this.sites[this.activeSiteId];
        if (site && site.targets) {
            site.targets.forEach(target => {
                const rangeRatio = target.range / this.radarRange;
                if (rangeRatio > 1) return;

                const x = rangeRatio * width;
                const altRatio = Math.min(target.altitude / 30000, 1);
                const y = height - altRatio * height;

                const isTracked = site.tracked && site.tracked.id === target.id;

                ctx.fillStyle = isTracked ? '#ff0000' : '#00ff00';
                ctx.beginPath();
                ctx.arc(x, y, 4, 0, Math.PI * 2);
                ctx.fill();
            });
        }

        // Draw antenna elevation line
        if (site) {
            const elRatio = site.antennaEl / 85;
            ctx.strokeStyle = '#00ff00';
            ctx.setLineDash([5, 5]);
            ctx.beginPath();
            ctx.moveTo(0, height - elRatio * height);
            ctx.lineTo(width, height - elRatio * height * 0.5);
            ctx.stroke();
            ctx.setLineDash([]);
        }
    }
}

// Initialize on page load
window.addEventListener('DOMContentLoaded', () => {
    window.samsim = new SAMSIMClient();
});
