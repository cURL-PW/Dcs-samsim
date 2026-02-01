/**
 * SAMSIM Client JavaScript - Enhanced Version
 * SA-2 (S-75) SAMSim Controller with detailed radar simulation
 */

class SAMSIMClient {
    constructor() {
        // WebSocket
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
        this.activeSiteId = null;
        this.selectedTrackId = null;

        // Update tracking
        this.lastUpdateTime = 0;
        this.updateCount = 0;
        this.updateRate = 0;

        // Radar display settings
        this.p19Range = 160000;
        this.snr75Range = 65000;

        // Canvas contexts
        this.p19Ctx = null;
        this.snr75Ctx = null;
        this.aScopeCtx = null;
        this.bScopeCtx = null;

        // Animation
        this.sweepAngle = 0;
        this.lastFrameTime = 0;
        this.sweepHistory = [];

        // System state names
        this.systemStateNames = ['OFFLINE', 'STARTUP', 'READY', 'ALERT', 'TRACKING', 'ENGAGED', 'COOLDOWN'];
        this.p19ModeNames = ['OFF', 'STANDBY', 'ROTATE', 'SECTOR'];
        this.snr75ModeNames = ['OFF', 'STANDBY', 'ACQUISITION', 'TRK-COARSE', 'TRK-FINE', 'GUIDANCE'];

        this.init();
    }

    init() {
        // Get canvas contexts
        const p19Canvas = document.getElementById('p19Scope');
        const snr75Canvas = document.getElementById('snr75Scope');
        const aScopeCanvas = document.getElementById('aScope');
        const bScopeCanvas = document.getElementById('bScope');

        if (p19Canvas) this.p19Ctx = p19Canvas.getContext('2d');
        if (snr75Canvas) this.snr75Ctx = snr75Canvas.getContext('2d');
        if (aScopeCanvas) this.aScopeCtx = aScopeCanvas.getContext('2d');
        if (bScopeCanvas) this.bScopeCtx = bScopeCanvas.getContext('2d');

        this.bindEvents();
        this.generateMissileIndicators();
        this.connect();
        this.animate();

        // Update rate calculation
        setInterval(() => {
            this.updateRate = this.updateCount;
            this.updateCount = 0;
            document.getElementById('updateRate').textContent = this.updateRate + ' Hz';
        }, 1000);
    }

    bindEvents() {
        // Site selection
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

        // Power controls
        document.getElementById('btnPowerOn')?.addEventListener('click', () => {
            this.sendCommand('set_system_state', { state: 1 }); // STARTUP
        });
        document.getElementById('btnPowerOff')?.addEventListener('click', () => {
            this.sendCommand('set_system_state', { state: 0 }); // OFFLINE
        });

        // P-19 mode
        document.getElementById('p19Mode')?.addEventListener('change', (e) => {
            this.sendCommand('set_p19_mode', { mode: parseInt(e.target.value) });
        });
        document.getElementById('p19Range')?.addEventListener('change', (e) => {
            this.p19Range = parseInt(e.target.value) * 1000;
        });

        // SNR-75 mode
        document.getElementById('snr75Mode')?.addEventListener('change', (e) => {
            this.sendCommand('set_snr75_mode', { mode: parseInt(e.target.value) });
        });
        document.getElementById('snr75Range')?.addEventListener('change', (e) => {
            this.snr75Range = parseInt(e.target.value) * 1000;
        });

        // Antenna command
        document.getElementById('btnCommandAntenna')?.addEventListener('click', () => {
            const az = parseFloat(document.getElementById('snr75Az').value) || 0;
            const el = parseFloat(document.getElementById('snr75El').value) || 5;
            this.sendCommand('command_antenna', { azimuth: az, elevation: el });
        });

        // Engagement controls
        document.getElementById('btnDesignate')?.addEventListener('click', () => {
            if (this.selectedTrackId) {
                this.sendCommand('designate_target', { targetId: this.selectedTrackId });
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

        // Engagement toggles
        document.getElementById('autoTrackToggle')?.addEventListener('change', (e) => {
            this.sendCommand('set_engagement', { autoTrack: e.target.checked });
        });
        document.getElementById('engAuthToggle')?.addEventListener('change', (e) => {
            this.sendCommand('set_engagement', { authorized: e.target.checked });
        });
        document.getElementById('autoEngToggle')?.addEventListener('change', (e) => {
            this.sendCommand('set_engagement', { autoEngage: e.target.checked });
        });
        document.getElementById('burstModeToggle')?.addEventListener('change', (e) => {
            this.sendCommand('set_engagement', { burstMode: e.target.checked });
        });

        // Radar click handlers
        document.getElementById('p19Scope')?.addEventListener('click', (e) => this.handleP19Click(e));
        document.getElementById('snr75Scope')?.addEventListener('click', (e) => this.handleSNR75Click(e));
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
            setTimeout(() => this.connect(), this.reconnectDelay);
        }
    }

    handleMessage(data) {
        try {
            const message = JSON.parse(data);
            if (message.type === 'state' || message.type === 'update') {
                this.updateState(message);
                this.updateCount++;
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
        this.updateUI();
    }

    updateUI() {
        this.updateConnectionStatus();

        // Mission time
        document.getElementById('missionTime').textContent = this.formatTime(this.missionTime);

        // Update site selector
        this.updateSiteSelector();

        // Update active site display
        if (this.activeSiteId && this.sites[this.activeSiteId]) {
            this.updateSiteDisplay(this.sites[this.activeSiteId]);
        }

        document.getElementById('lastUpdate').textContent = new Date().toLocaleTimeString();
    }

    updateConnectionStatus() {
        const statusDot = document.querySelector('.connection-status .status-dot');
        const statusText = document.querySelector('.connection-status .status-text');

        if (this.wsConnected && this.dcsConnected) {
            statusDot?.classList.remove('disconnected');
            statusDot?.classList.add('connected');
            if (statusText) statusText.textContent = 'Connected';
        } else {
            statusDot?.classList.remove('connected');
            statusDot?.classList.add('disconnected');
            if (statusText) statusText.textContent = 'Disconnected';
        }

        document.getElementById('wsStatus').textContent = this.wsConnected ? 'Connected' : 'Disconnected';
        document.getElementById('dcsStatus').textContent = this.dcsConnected ? 'Connected' : 'Not Connected';
    }

    updateSiteSelector() {
        const selector = document.getElementById('siteSelect');
        if (!selector) return;

        const currentValue = selector.value;
        const siteIds = Object.keys(this.sites);

        selector.innerHTML = '<option value="">-- Select --</option>';
        siteIds.forEach(siteId => {
            const option = document.createElement('option');
            option.value = siteId;
            option.textContent = siteId;
            selector.appendChild(option);
        });

        if (currentValue && siteIds.includes(currentValue)) {
            selector.value = currentValue;
        } else if (siteIds.length > 0 && !this.activeSiteId) {
            selector.value = siteIds[0];
            this.activeSiteId = siteIds[0];
        }
    }

    updateSiteDisplay(site) {
        // System state
        const stateName = this.systemStateNames[site.systemState] || 'UNKNOWN';
        document.getElementById('systemState').textContent = stateName;
        document.getElementById('systemState').className = 'state-value state-' + stateName.toLowerCase();

        // P-19 display
        if (site.p19) {
            document.getElementById('p19ModeDisplay').textContent = this.p19ModeNames[site.p19.mode] || 'OFF';
            document.getElementById('p19AntennaAz').textContent = site.p19.antennaAz?.toFixed(1) || '0';
            document.getElementById('p19Mode').value = site.p19.mode;
        }

        // SNR-75 display
        if (site.snr75) {
            document.getElementById('snr75ModeDisplay').textContent = this.snr75ModeNames[site.snr75.mode] || 'OFF';
            document.getElementById('snr75Mode').value = site.snr75.mode;
        }

        // Indicators
        const indPower = document.getElementById('indPower');
        const indP19 = document.getElementById('indP19');
        const indSNR = document.getElementById('indSNR');
        const indTrack = document.getElementById('indTrack');
        const indGuide = document.getElementById('indGuide');

        indPower?.classList.toggle('active', site.systemState >= 2);
        indP19?.classList.toggle('active', site.p19?.mode >= 2);
        indSNR?.classList.toggle('active', site.snr75?.mode >= 2);
        indTrack?.classList.toggle('active', site.snr75?.mode >= 3);
        indGuide?.classList.toggle('active', site.snr75?.mode >= 5);
        indGuide?.classList.toggle('danger', site.snr75?.mode >= 5);

        // EW target list
        this.updateEWTargetList(site.p19?.tracks || []);

        // Tracked target
        if (site.snr75?.tracked) {
            const t = site.snr75.tracked;
            document.getElementById('tgtId').textContent = t.id;
            document.getElementById('tgtRange').textContent = (t.range / 1000).toFixed(1) + ' km';
            document.getElementById('tgtAzimuth').textContent = t.azimuth?.toFixed(1) + '\u00b0';
            document.getElementById('tgtElevation').textContent = t.elevation?.toFixed(1) + '\u00b0';
            document.getElementById('tgtAltitude').textContent = t.altitude + ' m';
            document.getElementById('tgtSpeed').textContent = t.speed + ' m/s';
            document.getElementById('tgtHeading').textContent = t.heading + '\u00b0';
            document.getElementById('tgtClosure').textContent = t.closure + ' m/s';
            document.getElementById('tgtCrossing').textContent = t.crossing + '\u00b0';
        } else {
            ['tgtId', 'tgtRange', 'tgtAzimuth', 'tgtElevation', 'tgtAltitude', 'tgtSpeed', 'tgtHeading', 'tgtClosure', 'tgtCrossing'].forEach(id => {
                document.getElementById(id).textContent = '---';
            });
        }

        // Track quality
        const quality = site.snr75?.trackQuality || 0;
        document.getElementById('trackQuality').textContent = quality + '%';
        const qualityBar = document.getElementById('trackQualityBar');
        if (qualityBar) qualityBar.style.width = quality + '%';

        // Firing solution
        if (site.firingSolution) {
            const fs = site.firingSolution;
            const launchZoneEl = document.getElementById('launchZoneDisplay');
            const launchZoneText = document.getElementById('launchZone');

            launchZoneText.textContent = fs.launchZone || '---';
            launchZoneEl.className = 'zone-display zone-' + (fs.launchZone || 'none').toLowerCase();

            document.getElementById('pkValue').textContent = fs.killProbability + '%';
            const pkFill = document.getElementById('pkFill');
            if (pkFill) {
                pkFill.style.width = fs.killProbability + '%';
                pkFill.className = 'pk-fill pk-' + (fs.killProbability >= 60 ? 'high' : fs.killProbability >= 30 ? 'medium' : 'low');
            }

            document.getElementById('timeToIntercept').textContent = fs.timeToIntercept + ' sec';
            document.getElementById('leadAngle').textContent = fs.leadAngle + '\u00b0';
            document.getElementById('missileTOF').textContent = fs.timeToIntercept + ' sec';
        }

        // Missiles
        if (site.missiles) {
            document.getElementById('missilesReady').textContent = site.missiles.ready;
            document.getElementById('missilesInFlight').textContent = site.missiles.inFlight;

            for (let i = 0; i < 6; i++) {
                const indicator = document.getElementById(`missile-${i}`);
                if (indicator) {
                    indicator.classList.toggle('empty', i >= site.missiles.ready);
                }
            }
        }

        // Engagement toggles
        if (site.engagement) {
            document.getElementById('autoTrackToggle').checked = site.engagement.autoTrack;
            document.getElementById('engAuthToggle').checked = site.engagement.authorized;
            document.getElementById('autoEngToggle').checked = site.engagement.autoEngage;
            document.getElementById('burstModeToggle').checked = site.engagement.burstMode;
        }
    }

    updateEWTargetList(tracks) {
        const container = document.getElementById('ewTargetList');
        if (!container) return;

        if (!tracks || tracks.length === 0) {
            container.innerHTML = '<div class="no-targets">No tracks</div>';
            return;
        }

        container.innerHTML = '';
        tracks.forEach(track => {
            const item = document.createElement('div');
            item.className = 'target-item';
            if (track.id === this.selectedTrackId) {
                item.classList.add('selected');
            }

            item.innerHTML = `
                <span class="target-id">${track.id}</span>
                <span class="target-info">${(track.range / 1000).toFixed(0)} km / ${track.azimuth.toFixed(0)}\u00b0 / ${(track.altitude / 1000).toFixed(1)} km</span>
            `;

            item.addEventListener('click', () => {
                this.selectedTrackId = track.id;
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
        if (!this.wsConnected) return;

        const message = {
            type: 'init_site',
            siteId: siteId,
            groupName: groupName
        };

        this.ws.send(JSON.stringify(message));
        this.activeSiteId = siteId;
    }

    handleP19Click(event) {
        const rect = event.target.getBoundingClientRect();
        const centerX = 200;
        const centerY = 200;
        const x = event.clientX - rect.left - centerX;
        const y = centerY - (event.clientY - rect.top);

        const range = Math.sqrt(x * x + y * y) / 190 * this.p19Range;
        const azimuth = (Math.atan2(x, y) * 180 / Math.PI + 360) % 360;

        // Find closest track
        const site = this.sites[this.activeSiteId];
        if (site?.p19?.tracks) {
            let closest = null;
            let closestDist = Infinity;

            site.p19.tracks.forEach(track => {
                const tx = Math.sin(track.azimuth * Math.PI / 180) * track.range / this.p19Range * 190;
                const ty = Math.cos(track.azimuth * Math.PI / 180) * track.range / this.p19Range * 190;
                const dist = Math.sqrt((x - tx) ** 2 + (y - ty) ** 2);

                if (dist < closestDist && dist < 20) {
                    closestDist = dist;
                    closest = track;
                }
            });

            if (closest) {
                this.selectedTrackId = closest.id;
                this.updateEWTargetList(site.p19.tracks);
            }
        }
    }

    handleSNR75Click(event) {
        const rect = event.target.getBoundingClientRect();
        const centerX = 175;
        const centerY = 175;
        const x = event.clientX - rect.left - centerX;
        const y = centerY - (event.clientY - rect.top);

        const azimuth = (Math.atan2(x, y) * 180 / Math.PI + 360) % 360;

        // Command antenna to this azimuth
        document.getElementById('snr75Az').value = Math.round(azimuth);
    }

    animate(timestamp) {
        const deltaTime = timestamp - this.lastFrameTime;
        this.lastFrameTime = timestamp;

        const site = this.sites[this.activeSiteId];

        // Update P-19 sweep angle
        if (site?.p19?.mode === 2) {
            this.sweepAngle = site.p19.antennaAz || 0;
        }

        this.drawP19Radar(site);
        this.drawSNR75Radar(site);
        this.drawAScope(site);
        this.drawBScope(site);

        requestAnimationFrame((t) => this.animate(t));
    }

    drawP19Radar(site) {
        const ctx = this.p19Ctx;
        if (!ctx) return;

        const width = 400;
        const height = 400;
        const centerX = width / 2;
        const centerY = height / 2;
        const radius = 190;

        // Clear
        ctx.fillStyle = '#001100';
        ctx.fillRect(0, 0, width, height);

        // Range rings
        ctx.strokeStyle = '#003300';
        ctx.lineWidth = 1;
        for (let i = 1; i <= 4; i++) {
            ctx.beginPath();
            ctx.arc(centerX, centerY, radius * i / 4, 0, Math.PI * 2);
            ctx.stroke();

            const rangeKm = this.p19Range * i / 4 / 1000;
            ctx.fillStyle = '#004400';
            ctx.font = '10px monospace';
            ctx.fillText(rangeKm + 'km', centerX + 5, centerY - radius * i / 4 + 12);
        }

        // Azimuth lines
        for (let i = 0; i < 12; i++) {
            const angle = i * 30 * Math.PI / 180;
            ctx.beginPath();
            ctx.moveTo(centerX, centerY);
            ctx.lineTo(centerX + Math.sin(angle) * radius, centerY - Math.cos(angle) * radius);
            ctx.stroke();
        }

        // Cardinal directions
        ctx.fillStyle = '#00aa00';
        ctx.font = 'bold 12px monospace';
        ctx.fillText('N', centerX - 4, 15);
        ctx.fillText('S', centerX - 4, height - 5);
        ctx.fillText('E', width - 15, centerY + 4);
        ctx.fillText('W', 5, centerY + 4);

        // Sweep line
        if (site?.p19?.mode === 2) {
            const sweepRad = (site.p19.antennaAz || 0) * Math.PI / 180;

            // Afterglow effect
            for (let i = 0; i < 30; i++) {
                const fadeAngle = sweepRad - i * 0.02;
                const alpha = 0.3 * (1 - i / 30);
                ctx.strokeStyle = `rgba(0, 255, 0, ${alpha})`;
                ctx.lineWidth = 2;
                ctx.beginPath();
                ctx.moveTo(centerX, centerY);
                ctx.lineTo(centerX + Math.sin(fadeAngle) * radius, centerY - Math.cos(fadeAngle) * radius);
                ctx.stroke();
            }

            // Main sweep
            ctx.strokeStyle = '#00ff00';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(centerX, centerY);
            ctx.lineTo(centerX + Math.sin(sweepRad) * radius, centerY - Math.cos(sweepRad) * radius);
            ctx.stroke();
        }

        // Draw tracks
        if (site?.p19?.tracks) {
            site.p19.tracks.forEach(track => {
                const rangeRatio = track.range / this.p19Range;
                if (rangeRatio > 1) return;

                const azRad = track.azimuth * Math.PI / 180;
                const x = centerX + Math.sin(azRad) * radius * rangeRatio;
                const y = centerY - Math.cos(azRad) * radius * rangeRatio;

                const isSelected = track.id === this.selectedTrackId;

                ctx.fillStyle = isSelected ? '#ffff00' : '#00ff00';
                ctx.beginPath();
                ctx.arc(x, y, isSelected ? 6 : 4, 0, Math.PI * 2);
                ctx.fill();

                ctx.fillStyle = isSelected ? '#ffff00' : '#00aa00';
                ctx.font = '9px monospace';
                ctx.fillText(track.id, x + 8, y - 3);
            });
        }

        // Center
        ctx.fillStyle = '#00ff00';
        ctx.beginPath();
        ctx.arc(centerX, centerY, 3, 0, Math.PI * 2);
        ctx.fill();
    }

    drawSNR75Radar(site) {
        const ctx = this.snr75Ctx;
        if (!ctx) return;

        const width = 350;
        const height = 350;
        const centerX = width / 2;
        const centerY = height / 2;
        const radius = 165;

        ctx.fillStyle = '#001100';
        ctx.fillRect(0, 0, width, height);

        // Range rings
        ctx.strokeStyle = '#003300';
        for (let i = 1; i <= 4; i++) {
            ctx.beginPath();
            ctx.arc(centerX, centerY, radius * i / 4, 0, Math.PI * 2);
            ctx.stroke();
        }

        // Azimuth lines
        for (let i = 0; i < 8; i++) {
            const angle = i * 45 * Math.PI / 180;
            ctx.beginPath();
            ctx.moveTo(centerX, centerY);
            ctx.lineTo(centerX + Math.sin(angle) * radius, centerY - Math.cos(angle) * radius);
            ctx.stroke();
        }

        // Antenna direction
        if (site?.snr75) {
            const azRad = (site.snr75.antennaAz || 0) * Math.PI / 180;

            // Beam width indicator
            ctx.fillStyle = 'rgba(0, 100, 0, 0.3)';
            ctx.beginPath();
            ctx.moveTo(centerX, centerY);
            ctx.arc(centerX, centerY, radius, azRad - Math.PI/2 - 0.1, azRad - Math.PI/2 + 0.1);
            ctx.closePath();
            ctx.fill();

            // Antenna line
            ctx.strokeStyle = '#00ff00';
            ctx.lineWidth = 2;
            ctx.setLineDash([5, 5]);
            ctx.beginPath();
            ctx.moveTo(centerX, centerY);
            ctx.lineTo(centerX + Math.sin(azRad) * radius, centerY - Math.cos(azRad) * radius);
            ctx.stroke();
            ctx.setLineDash([]);
        }

        // Tracked target
        if (site?.snr75?.tracked) {
            const t = site.snr75.tracked;
            const rangeRatio = t.range / this.snr75Range;
            if (rangeRatio <= 1) {
                const azRad = t.azimuth * Math.PI / 180;
                const x = centerX + Math.sin(azRad) * radius * rangeRatio;
                const y = centerY - Math.cos(azRad) * radius * rangeRatio;

                // Target marker
                ctx.strokeStyle = '#ff0000';
                ctx.lineWidth = 2;
                ctx.beginPath();
                ctx.moveTo(x - 10, y);
                ctx.lineTo(x + 10, y);
                ctx.moveTo(x, y - 10);
                ctx.lineTo(x, y + 10);
                ctx.stroke();

                // Strobe
                ctx.fillStyle = '#ff0000';
                ctx.beginPath();
                ctx.arc(x, y, 5, 0, Math.PI * 2);
                ctx.fill();

                // Range arc
                ctx.strokeStyle = 'rgba(255, 0, 0, 0.5)';
                ctx.beginPath();
                ctx.arc(centerX, centerY, radius * rangeRatio, 0, Math.PI * 2);
                ctx.stroke();
            }
        }

        // Engagement zone
        ctx.strokeStyle = 'rgba(255, 100, 0, 0.4)';
        ctx.setLineDash([5, 5]);

        const minRange = 7000 / this.snr75Range * radius;
        const maxRange = 45000 / this.snr75Range * radius;

        ctx.beginPath();
        ctx.arc(centerX, centerY, minRange, 0, Math.PI * 2);
        ctx.stroke();
        ctx.beginPath();
        ctx.arc(centerX, centerY, maxRange, 0, Math.PI * 2);
        ctx.stroke();

        ctx.setLineDash([]);

        // Center
        ctx.fillStyle = '#00ff00';
        ctx.beginPath();
        ctx.arc(centerX, centerY, 3, 0, Math.PI * 2);
        ctx.fill();
    }

    drawAScope(site) {
        const ctx = this.aScopeCtx;
        if (!ctx) return;

        const width = 200;
        const height = 120;

        ctx.fillStyle = '#001100';
        ctx.fillRect(0, 0, width, height);

        // Grid
        ctx.strokeStyle = '#003300';
        for (let i = 1; i < 4; i++) {
            ctx.beginPath();
            ctx.moveTo(width * i / 4, 0);
            ctx.lineTo(width * i / 4, height);
            ctx.stroke();
        }
        for (let i = 1; i < 3; i++) {
            ctx.beginPath();
            ctx.moveTo(0, height * i / 3);
            ctx.lineTo(width, height * i / 3);
            ctx.stroke();
        }

        // Noise floor
        ctx.strokeStyle = '#004400';
        ctx.beginPath();
        ctx.moveTo(0, height * 0.8);
        for (let x = 0; x < width; x++) {
            const noise = Math.random() * 10;
            ctx.lineTo(x, height * 0.8 - noise);
        }
        ctx.stroke();

        // Target return
        if (site?.snr75?.tracked && site?.snr75?.aScopeData) {
            const data = site.snr75.aScopeData;
            ctx.strokeStyle = '#00ff00';
            ctx.lineWidth = 2;
            ctx.beginPath();

            for (let i = 0; i < data.length; i++) {
                const x = (i / data.length) * width;
                const y = height - data[i] * height * 0.9;
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
            ctx.stroke();
        }

        // Range marker
        if (site?.snr75?.tracked) {
            const rangeRatio = site.snr75.tracked.range / this.snr75Range;
            const markerX = rangeRatio * width;

            ctx.strokeStyle = '#ff0000';
            ctx.lineWidth = 1;
            ctx.setLineDash([3, 3]);
            ctx.beginPath();
            ctx.moveTo(markerX, 0);
            ctx.lineTo(markerX, height);
            ctx.stroke();
            ctx.setLineDash([]);

            ctx.fillStyle = '#ff0000';
            ctx.font = '10px monospace';
            ctx.fillText((site.snr75.tracked.range / 1000).toFixed(1) + 'km', markerX + 3, 12);
        }
    }

    drawBScope(site) {
        const ctx = this.bScopeCtx;
        if (!ctx) return;

        const width = 200;
        const height = 150;

        ctx.fillStyle = '#001100';
        ctx.fillRect(0, 0, width, height);

        // Grid
        ctx.strokeStyle = '#003300';
        for (let i = 1; i < 4; i++) {
            ctx.beginPath();
            ctx.moveTo(width * i / 4, 0);
            ctx.lineTo(width * i / 4, height);
            ctx.stroke();
        }
        for (let i = 1; i < 4; i++) {
            ctx.beginPath();
            ctx.moveTo(0, height * i / 4);
            ctx.lineTo(width, height * i / 4);
            ctx.stroke();
        }

        // Labels
        ctx.fillStyle = '#004400';
        ctx.font = '9px monospace';
        ctx.fillText('0', 2, height - 2);
        ctx.fillText((this.snr75Range / 1000) + 'km', width - 30, height - 2);
        ctx.fillText('30km', width - 25, 10);
        ctx.fillText('0', 2, 10);

        // Target
        if (site?.snr75?.tracked) {
            const t = site.snr75.tracked;
            const rangeRatio = t.range / this.snr75Range;
            const altRatio = Math.min(t.altitude / 30000, 1);

            const x = rangeRatio * width;
            const y = height - altRatio * height;

            ctx.fillStyle = '#ff0000';
            ctx.beginPath();
            ctx.arc(x, y, 5, 0, Math.PI * 2);
            ctx.fill();

            // Antenna elevation line
            const elRad = (site.snr75.antennaEl || 0) * Math.PI / 180;
            ctx.strokeStyle = '#00ff00';
            ctx.setLineDash([3, 3]);
            ctx.beginPath();
            ctx.moveTo(0, height);
            ctx.lineTo(width, height - Math.tan(elRad) * width / (this.snr75Range / 30000));
            ctx.stroke();
            ctx.setLineDash([]);
        }
    }
}

// Initialize
window.addEventListener('DOMContentLoaded', () => {
    window.samsim = new SAMSIMClient();
});
