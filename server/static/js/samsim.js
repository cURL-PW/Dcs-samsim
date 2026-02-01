/**
 * Eastern SAM Simulator - DCS World
 * Multi-System Support: SA-2, SA-3, SA-6, SA-10, SA-11
 */

class SAMSimClient {
    constructor() {
        this.ws = null;
        this.state = null;
        this.selectedTarget = null;
        this.currentSystem = null;
        this.updateCount = 0;
        this.lastUpdateTime = Date.now();

        // Radar display settings
        this.ewRange = 160;  // km
        this.fcRange = 65;   // km
        this.ewSweepAngle = 0;
        this.fcSweepAngle = 0;

        // Contact history for afterglow effect
        this.contactHistory = [];

        // System configurations
        this.systemConfigs = {
            SA2: {
                name: 'SA-2 Guideline',
                sovietName: 'S-75 Dvina',
                ewRadar: 'P-19 "Flat Face"',
                fcRadar: 'SNR-75 "Fan Song"',
                missile: 'V-750',
                ewMaxRange: 160,
                fcMaxRange: 65,
                missileMaxRange: 45,
                missileMinRange: 7,
                missiles: 6,
                multiChannel: false
            },
            SA3: {
                name: 'SA-3 Goa',
                sovietName: 'S-125 Neva/Pechora',
                ewRadar: 'P-15 "Flat Face"',
                fcRadar: 'SNR-125 "Low Blow"',
                missile: '5V27',
                ewMaxRange: 150,
                fcMaxRange: 50,
                missileMaxRange: 25,
                missileMinRange: 3.5,
                missiles: 4,
                multiChannel: false
            },
            SA6: {
                name: 'SA-6 Gainful',
                sovietName: '2K12 Kub',
                ewRadar: '1S91 "Straight Flush" Search',
                fcRadar: '1S91 "Straight Flush" Track',
                missile: '3M9',
                ewMaxRange: 75,
                fcMaxRange: 28,
                missileMaxRange: 24,
                missileMinRange: 4,
                missiles: 3,
                multiChannel: false,
                combined: true  // Combined search/track radar
            },
            SA10: {
                name: 'SA-10 Grumble',
                sovietName: 'S-300PS',
                ewRadar: '64N6 "Big Bird"',
                fcRadar: '30N6 "Flap Lid"',
                missile: '5V55R',
                ewMaxRange: 300,
                fcMaxRange: 200,
                missileMaxRange: 90,
                missileMinRange: 5,
                missiles: 16,
                multiChannel: true,
                channels: 6
            },
            SA11: {
                name: 'SA-11 Gadfly',
                sovietName: '9K37 Buk',
                ewRadar: '9S18 "Snow Drift"',
                fcRadar: '9S35 "Fire Dome"',
                missile: '9M38',
                ewMaxRange: 100,
                fcMaxRange: 42,
                missileMaxRange: 35,
                missileMinRange: 3,
                missiles: 16,
                multiChannel: true,
                channels: 4  // 4 TELARs
            }
        };

        this.init();
    }

    init() {
        this.initCanvases();
        this.initWebSocket();
        this.initEventListeners();
        this.startAnimationLoop();
    }

    initCanvases() {
        // Early Warning / Search Radar
        this.ewCanvas = document.getElementById('ewScope');
        this.ewCtx = this.ewCanvas ? this.ewCanvas.getContext('2d') : null;

        // Fire Control Radar
        this.fcCanvas = document.getElementById('fcScope');
        this.fcCtx = this.fcCanvas ? this.fcCanvas.getContext('2d') : null;

        // A-Scope
        this.aScopeCanvas = document.getElementById('aScope');
        this.aScopeCtx = this.aScopeCanvas ? this.aScopeCanvas.getContext('2d') : null;

        // B-Scope
        this.bScopeCanvas = document.getElementById('bScope');
        this.bScopeCtx = this.bScopeCanvas ? this.bScopeCanvas.getContext('2d') : null;
    }

    initWebSocket() {
        const wsUrl = `ws://${window.location.hostname}:8081`;

        try {
            this.ws = new WebSocket(wsUrl);

            this.ws.onopen = () => {
                this.updateConnectionStatus(true);
                this.log('Connected to server', 'info');
            };

            this.ws.onclose = () => {
                this.updateConnectionStatus(false);
                this.log('Disconnected from server', 'warning');
                setTimeout(() => this.initWebSocket(), 3000);
            };

            this.ws.onerror = (error) => {
                this.log('WebSocket error', 'error');
            };

            this.ws.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);
                    this.handleServerMessage(data);
                } catch (e) {
                    console.error('Failed to parse message:', e);
                }
            };
        } catch (e) {
            this.log('Failed to connect', 'error');
            setTimeout(() => this.initWebSocket(), 3000);
        }
    }

    initEventListeners() {
        // System selector
        const samSelect = document.getElementById('samSystemSelect');
        if (samSelect) {
            samSelect.addEventListener('change', (e) => this.selectSystem(e.target.value));
        }

        // Power controls
        document.getElementById('btnPowerOn')?.addEventListener('click', () => this.sendPowerCommand('ON'));
        document.getElementById('btnPowerOff')?.addEventListener('click', () => this.sendPowerCommand('OFF'));

        // Radar mode controls
        document.getElementById('ewMode')?.addEventListener('change', (e) => this.sendEWModeCommand(e.target.value));
        document.getElementById('fcMode')?.addEventListener('change', (e) => this.sendFCModeCommand(e.target.value));

        // Range controls
        document.getElementById('ewRange')?.addEventListener('change', (e) => {
            this.ewRange = parseInt(e.target.value);
        });
        document.getElementById('fcRange')?.addEventListener('change', (e) => {
            this.fcRange = parseInt(e.target.value);
        });

        // Antenna controls
        document.getElementById('btnCommandAntenna')?.addEventListener('click', () => this.sendAntennaCommand());

        // Engagement controls
        document.getElementById('btnDesignate')?.addEventListener('click', () => this.designateTarget());
        document.getElementById('btnDropTrack')?.addEventListener('click', () => this.dropTrack());
        document.getElementById('btnLaunch')?.addEventListener('click', () => this.launchMissile());

        // Site controls
        document.getElementById('initSiteBtn')?.addEventListener('click', () => this.showInitSiteModal());
        document.getElementById('confirmInitSite')?.addEventListener('click', () => this.initializeSite());
        document.getElementById('cancelInitSite')?.addEventListener('click', () => this.hideInitSiteModal());
    }

    selectSystem(systemType) {
        if (!systemType) return;

        this.currentSystem = systemType;
        const config = this.systemConfigs[systemType];

        if (!config) return;

        // Update UI titles
        document.getElementById('systemTitle').textContent = config.name;
        document.getElementById('systemSubtitle').textContent = config.sovietName;
        document.getElementById('ewRadarTitle').textContent = config.ewRadar;
        document.getElementById('fcRadarTitle').textContent = config.fcRadar;
        document.getElementById('missileTitle').textContent = `${config.missile} Missiles`;
        document.getElementById('currentSystem').textContent = config.name;

        // Update range defaults
        this.ewRange = config.ewMaxRange;
        this.fcRange = config.fcMaxRange;

        // Update range selects
        this.updateRangeSelect('ewRange', config.ewMaxRange);
        this.updateRangeSelect('fcRange', config.fcMaxRange);

        // Show/hide multi-channel panel
        const channelPanel = document.getElementById('channelPanel');
        if (channelPanel) {
            channelPanel.style.display = config.multiChannel ? 'block' : 'none';
            if (config.multiChannel) {
                this.initChannelGrid(config.channels);
            }
        }

        // Update indicator labels based on system
        this.updateIndicatorLabels(systemType);

        // Send system selection to server
        this.sendCommand({ type: 'SELECT_SYSTEM', systemType: systemType });

        this.log(`Selected ${config.name}`, 'info');
    }

    updateRangeSelect(selectId, maxRange) {
        const select = document.getElementById(selectId);
        if (!select) return;

        // Set to closest available option
        const options = select.options;
        for (let i = options.length - 1; i >= 0; i--) {
            if (parseInt(options[i].value) <= maxRange) {
                select.value = options[i].value;
                break;
            }
        }
    }

    updateIndicatorLabels(systemType) {
        const config = this.systemConfigs[systemType];
        if (!config) return;

        // Update indicator labels based on system
        const ewLabel = document.querySelector('#indEW .indicator-label');
        const fcLabel = document.querySelector('#indFC .indicator-label');

        if (ewLabel) {
            switch(systemType) {
                case 'SA2': ewLabel.textContent = 'P-19'; break;
                case 'SA3': ewLabel.textContent = 'P-15'; break;
                case 'SA6': ewLabel.textContent = '1S91'; break;
                case 'SA10': ewLabel.textContent = 'BB'; break;
                case 'SA11': ewLabel.textContent = 'SD'; break;
            }
        }

        if (fcLabel) {
            switch(systemType) {
                case 'SA2': fcLabel.textContent = 'SNR'; break;
                case 'SA3': fcLabel.textContent = 'LB'; break;
                case 'SA6': fcLabel.textContent = 'TRK'; break;
                case 'SA10': fcLabel.textContent = 'FL'; break;
                case 'SA11': fcLabel.textContent = 'FD'; break;
            }
        }
    }

    initChannelGrid(numChannels) {
        const grid = document.getElementById('channelGrid');
        if (!grid) return;

        grid.innerHTML = '';

        for (let i = 1; i <= numChannels; i++) {
            const channel = document.createElement('div');
            channel.className = 'channel-item';
            channel.id = `channel${i}`;
            channel.innerHTML = `
                <div class="channel-num">CH ${i}</div>
                <div class="channel-status" id="ch${i}Status">IDLE</div>
                <div class="channel-target" id="ch${i}Target">---</div>
            `;
            channel.addEventListener('click', () => this.selectChannel(i));
            grid.appendChild(channel);
        }
    }

    selectChannel(channelNum) {
        // Highlight selected channel
        document.querySelectorAll('.channel-item').forEach(el => el.classList.remove('selected'));
        document.getElementById(`channel${channelNum}`)?.classList.add('selected');

        this.sendCommand({ type: 'SELECT_CHANNEL', channel: channelNum });
    }

    handleServerMessage(data) {
        // Handle different message types
        if (data.type === 'state') {
            this.state = data.state;
            this.updateDisplay();
        } else if (data.type === 'response') {
            if (data.success) {
                this.log(data.message, 'success');
            } else {
                this.log(data.message, 'error');
            }
        } else if (data.systemType) {
            // Direct state update
            this.state = data;
            this.currentSystem = data.systemType;
            this.updateDisplay();
        }

        this.updateCount++;
        this.updateRate();
    }

    updateDisplay() {
        if (!this.state) return;

        // Update based on system type
        switch(this.state.systemType) {
            case 'SA2':
                this.updateSA2Display();
                break;
            case 'SA3':
                this.updateSA3Display();
                break;
            case 'SA6':
                this.updateSA6Display();
                break;
            case 'SA10':
                this.updateSA10Display();
                break;
            case 'SA11':
                this.updateSA11Display();
                break;
            default:
                this.updateGenericDisplay();
        }

        // Common updates
        this.updateTargetList();
        this.updateFiringSolution();
        this.updateMissileStatus();
    }

    updateSA2Display() {
        const state = this.state;

        // P-19 radar state
        if (state.p19) {
            document.getElementById('ewModeDisplay').textContent = state.p19.modeName || 'OFF';
            document.getElementById('ewAntennaAz').textContent = Math.round(state.p19.azimuth || 0);
            this.ewSweepAngle = state.p19.azimuth || 0;

            this.updateIndicator('indEW', state.p19.mode > 0);
        }

        // SNR-75 radar state
        if (state.snr75) {
            document.getElementById('fcModeDisplay').textContent = state.snr75.modeName || 'OFF';
            this.fcSweepAngle = state.snr75.antennaAz || 0;

            this.updateIndicator('indFC', state.snr75.mode > 0);
            this.updateIndicator('indTrack', state.snr75.mode >= 3);
            this.updateIndicator('indGuide', state.snr75.mode >= 5);
        }

        // Track data
        if (state.track && state.track.valid) {
            this.updateTrackData(state.track);
        }
    }

    updateSA3Display() {
        const state = this.state;

        if (state.p15) {
            document.getElementById('ewModeDisplay').textContent = state.p15.modeName || 'OFF';
            document.getElementById('ewAntennaAz').textContent = Math.round(state.p15.azimuth || 0);
            this.ewSweepAngle = state.p15.azimuth || 0;
            this.updateIndicator('indEW', state.p15.mode > 0);
        }

        if (state.snr125) {
            document.getElementById('fcModeDisplay').textContent = state.snr125.modeName || 'OFF';
            this.fcSweepAngle = state.snr125.antennaAz || 0;
            this.updateIndicator('indFC', state.snr125.mode > 0);
            this.updateIndicator('indTrack', state.snr125.mode >= 3);
            this.updateIndicator('indGuide', state.snr125.mode >= 5);
        }

        if (state.track && state.track.valid) {
            this.updateTrackData(state.track);
        }
    }

    updateSA6Display() {
        const state = this.state;

        if (state.radar) {
            document.getElementById('ewModeDisplay').textContent = state.radar.modeName || 'OFF';
            document.getElementById('ewAntennaAz').textContent = Math.round(state.radar.searchAzimuth || 0);
            this.ewSweepAngle = state.radar.searchAzimuth || 0;

            document.getElementById('fcModeDisplay').textContent = state.radar.modeName || 'OFF';
            this.fcSweepAngle = state.radar.trackAzimuth || 0;

            this.updateIndicator('indEW', state.radar.mode >= 2);
            this.updateIndicator('indFC', state.radar.mode >= 4);
            this.updateIndicator('indTrack', state.radar.mode >= 5);
            this.updateIndicator('indGuide', state.radar.mode >= 6);

            // CW illumination indicator
            if (state.radar.cwPower > 0) {
                document.getElementById('indGuide')?.classList.add('active');
            }
        }

        if (state.track && state.track.valid) {
            this.updateTrackData(state.track);
        }
    }

    updateSA10Display() {
        const state = this.state;

        if (state.bigBird) {
            document.getElementById('ewModeDisplay').textContent = state.bigBird.modeName || 'OFF';
            document.getElementById('ewAntennaAz').textContent = Math.round(state.bigBird.azimuth || 0);
            this.ewSweepAngle = state.bigBird.azimuth || 0;
            this.updateIndicator('indEW', state.bigBird.mode > 0);
        }

        if (state.flapLid) {
            document.getElementById('fcModeDisplay').textContent =
                state.flapLid.mode > 0 ? 'ACTIVE' : 'OFF';
            this.updateIndicator('indFC', state.flapLid.mode > 0);
        }

        // Update channels
        if (state.channels) {
            this.updateChannels(state.channels);
        }
    }

    updateSA11Display() {
        const state = this.state;

        if (state.snowDrift) {
            document.getElementById('ewModeDisplay').textContent = state.snowDrift.modeName || 'OFF';
            document.getElementById('ewAntennaAz').textContent = Math.round(state.snowDrift.azimuth || 0);
            this.ewSweepAngle = state.snowDrift.azimuth || 0;
            this.updateIndicator('indEW', state.snowDrift.mode > 0);
        }

        // Update TELARs
        if (state.telars) {
            this.updateTelars(state.telars);
        }
    }

    updateGenericDisplay() {
        // Fallback for unknown system types
    }

    updateChannels(channels) {
        channels.forEach((channel, index) => {
            const statusEl = document.getElementById(`ch${index + 1}Status`);
            const targetEl = document.getElementById(`ch${index + 1}Target`);
            const channelEl = document.getElementById(`channel${index + 1}`);

            if (statusEl) {
                statusEl.textContent = channel.modeName || 'IDLE';
                statusEl.className = 'channel-status ' + (channel.active ? 'active' : '');
            }

            if (targetEl) {
                targetEl.textContent = channel.trackValid ?
                    `${Math.round(channel.trackRange / 1000)}km` : '---';
            }

            if (channelEl) {
                channelEl.classList.toggle('tracking', channel.trackValid);
                channelEl.classList.toggle('guidance', channel.mode >= 4);
            }
        });
    }

    updateTelars(telars) {
        telars.forEach((telar, index) => {
            const statusEl = document.getElementById(`ch${index + 1}Status`);
            const targetEl = document.getElementById(`ch${index + 1}Target`);
            const channelEl = document.getElementById(`channel${index + 1}`);

            if (statusEl) {
                let status = telar.modeName || 'OFF';
                if (telar.cwPower > 0) status = 'ILLUM';
                statusEl.textContent = status;
            }

            if (targetEl) {
                if (telar.trackValid) {
                    targetEl.textContent = `${Math.round(telar.trackRange / 1000)}km`;
                } else {
                    targetEl.textContent = `MSL:${telar.missilesReady}`;
                }
            }

            if (channelEl) {
                channelEl.classList.toggle('tracking', telar.trackValid);
                channelEl.classList.toggle('guidance', telar.mode >= 4);
            }
        });
    }

    updateTrackData(track) {
        document.getElementById('tgtId').textContent = track.id || '---';
        document.getElementById('tgtRange').textContent = track.range ?
            `${(track.range / 1000).toFixed(1)} km` : '---';
        document.getElementById('tgtAzimuth').textContent = track.azimuth ?
            `${track.azimuth.toFixed(1)}°` : '---';
        document.getElementById('tgtElevation').textContent = track.elevation ?
            `${track.elevation.toFixed(1)}°` : '---';
        document.getElementById('tgtAltitude').textContent = track.altitude ?
            `${Math.round(track.altitude)} m` : '---';
        document.getElementById('tgtSpeed').textContent = track.speed ?
            `${Math.round(track.speed * 3.6)} km/h` : '---';
        document.getElementById('tgtHeading').textContent = track.heading ?
            `${Math.round(track.heading)}°` : '---';

        // Track quality
        const quality = this.state.snr75?.trackQuality ||
                       this.state.snr125?.trackQuality ||
                       this.state.radar?.trackQuality || 0;
        const qualityPercent = Math.round(quality * 100);
        document.getElementById('trackQuality').textContent = `${qualityPercent}%`;
        const qualityBar = document.getElementById('trackQualityBar');
        if (qualityBar) {
            qualityBar.style.width = `${qualityPercent}%`;
        }

        this.updateIndicator('indTrack', track.valid);
    }

    updateTargetList() {
        const list = document.getElementById('ewTargetList');
        if (!list || !this.state?.contacts) return;

        if (this.state.contacts.length === 0) {
            list.innerHTML = '<div class="no-targets">No tracks</div>';
            return;
        }

        list.innerHTML = this.state.contacts.map(contact => `
            <div class="target-item ${this.selectedTarget === contact.id ? 'selected' : ''}"
                 onclick="window.samSim.selectTarget(${contact.id})">
                <div class="target-info">
                    <span class="target-type">${contact.typeName || 'Unknown'}</span>
                    <span class="target-id">#${contact.id}</span>
                </div>
                <div class="target-data">
                    <span>${(contact.range / 1000).toFixed(1)} km</span>
                    <span>${contact.azimuth.toFixed(0)}°</span>
                    <span>${Math.round(contact.altitude)}m</span>
                </div>
            </div>
        `).join('');
    }

    updateFiringSolution() {
        const solution = this.state?.firingSolution;
        if (!solution) return;

        // Launch zone
        const zoneDisplay = document.getElementById('launchZoneDisplay');
        const zoneText = document.getElementById('launchZone');

        if (solution.valid && solution.inEnvelope) {
            zoneDisplay?.classList.add('in-zone');
            zoneDisplay?.classList.remove('out-zone');
            zoneText.textContent = 'IN ZONE';
        } else {
            zoneDisplay?.classList.remove('in-zone');
            zoneDisplay?.classList.add('out-zone');
            zoneText.textContent = solution.inRangeMax === false ? 'TOO FAR' :
                                   solution.inRangeMin === false ? 'TOO CLOSE' :
                                   solution.inAltitude === false ? 'ALT' : 'NO SOL';
        }

        // Pk gauge
        const pk = Math.round((solution.pk || 0) * 100);
        document.getElementById('pkValue').textContent = `${pk}%`;
        const pkFill = document.getElementById('pkFill');
        if (pkFill) {
            pkFill.style.width = `${pk}%`;
            pkFill.className = 'pk-fill ' + (pk >= 70 ? 'high' : pk >= 40 ? 'medium' : 'low');
        }

        // Time to intercept
        document.getElementById('timeToIntercept').textContent =
            solution.timeToIntercept ? `${solution.timeToIntercept.toFixed(1)} sec` : '--- sec';

        // Missile range info
        const config = this.systemConfigs[this.currentSystem];
        if (config) {
            document.getElementById('missileRange').textContent = `${config.missileMaxRange} km`;
            document.getElementById('minRange').textContent = `${config.missileMinRange} km`;
        }
    }

    updateMissileStatus() {
        const missiles = this.state?.missiles;
        if (!missiles) return;

        const ready = missiles.ready || missiles.totalReady || 0;
        const total = this.systemConfigs[this.currentSystem]?.missiles || ready;

        document.getElementById('missilesReady').textContent = ready;
        document.getElementById('missilesTotal').textContent = `/ ${total} Ready`;
        document.getElementById('missilesInFlight').textContent = missiles.inFlight || 0;

        // Update missile indicators
        const indicators = document.getElementById('missileIndicators');
        if (indicators) {
            indicators.innerHTML = '';
            for (let i = 0; i < total; i++) {
                const indicator = document.createElement('div');
                indicator.className = 'missile-indicator ' + (i < ready ? 'ready' : 'empty');
                indicators.appendChild(indicator);
            }
        }
    }

    updateIndicator(id, active) {
        const indicator = document.getElementById(id);
        if (indicator) {
            indicator.classList.toggle('active', active);
        }
    }

    // Radar drawing methods
    startAnimationLoop() {
        const animate = () => {
            this.drawRadars();
            requestAnimationFrame(animate);
        };
        animate();
    }

    drawRadars() {
        this.drawEWRadar();
        this.drawFCRadar();
        this.drawAScope();
        this.drawBScope();
    }

    drawEWRadar() {
        if (!this.ewCtx) return;

        const ctx = this.ewCtx;
        const canvas = this.ewCanvas;
        const cx = canvas.width / 2;
        const cy = canvas.height / 2;
        const radius = Math.min(cx, cy) - 10;

        // Clear
        ctx.fillStyle = '#001a00';
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        // Draw range rings
        ctx.strokeStyle = '#003300';
        ctx.lineWidth = 1;
        for (let i = 1; i <= 4; i++) {
            ctx.beginPath();
            ctx.arc(cx, cy, radius * i / 4, 0, Math.PI * 2);
            ctx.stroke();
        }

        // Draw bearing lines
        for (let i = 0; i < 12; i++) {
            const angle = (i * 30 - 90) * Math.PI / 180;
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.lineTo(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius);
            ctx.stroke();
        }

        // Draw range labels
        ctx.fillStyle = '#00ff00';
        ctx.font = '10px monospace';
        ctx.textAlign = 'center';
        for (let i = 1; i <= 4; i++) {
            const rangeKm = Math.round(this.ewRange * i / 4);
            ctx.fillText(`${rangeKm}`, cx + 5, cy - radius * i / 4 + 12);
        }

        // Draw sweep
        const sweepAngle = (this.ewSweepAngle - 90) * Math.PI / 180;
        ctx.strokeStyle = '#00ff00';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.lineTo(cx + Math.cos(sweepAngle) * radius, cy + Math.sin(sweepAngle) * radius);
        ctx.stroke();

        // Draw afterglow
        ctx.strokeStyle = 'rgba(0, 255, 0, 0.3)';
        for (let i = 1; i <= 30; i++) {
            const trailAngle = sweepAngle - i * 0.02;
            const alpha = 0.3 * (1 - i / 30);
            ctx.strokeStyle = `rgba(0, 255, 0, ${alpha})`;
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.lineTo(cx + Math.cos(trailAngle) * radius, cy + Math.sin(trailAngle) * radius);
            ctx.stroke();
        }

        // Draw contacts
        if (this.state?.contacts) {
            this.state.contacts.forEach(contact => {
                const range = contact.range / 1000;  // Convert to km
                if (range <= this.ewRange) {
                    const normalizedRange = range / this.ewRange;
                    const contactAngle = (contact.azimuth - 90) * Math.PI / 180;
                    const x = cx + Math.cos(contactAngle) * radius * normalizedRange;
                    const y = cy + Math.sin(contactAngle) * radius * normalizedRange;

                    // Draw contact
                    ctx.fillStyle = contact.id === this.selectedTarget ? '#ff0' : '#0f0';
                    ctx.beginPath();
                    ctx.arc(x, y, 4, 0, Math.PI * 2);
                    ctx.fill();

                    // Draw velocity vector
                    if (contact.heading !== undefined && contact.speed > 10) {
                        const headingRad = (contact.heading - 90) * Math.PI / 180;
                        const vecLength = Math.min(20, contact.speed / 20);
                        ctx.strokeStyle = '#0f0';
                        ctx.lineWidth = 1;
                        ctx.beginPath();
                        ctx.moveTo(x, y);
                        ctx.lineTo(x + Math.cos(headingRad) * vecLength, y + Math.sin(headingRad) * vecLength);
                        ctx.stroke();
                    }
                }
            });
        }

        // Draw selected contact highlight
        if (this.state?.selectedContact) {
            const contact = this.state.contacts?.find(c => c.id === this.state.selectedContact);
            if (contact) {
                const range = contact.range / 1000;
                if (range <= this.ewRange) {
                    const normalizedRange = range / this.ewRange;
                    const contactAngle = (contact.azimuth - 90) * Math.PI / 180;
                    const x = cx + Math.cos(contactAngle) * radius * normalizedRange;
                    const y = cy + Math.sin(contactAngle) * radius * normalizedRange;

                    ctx.strokeStyle = '#ff0';
                    ctx.lineWidth = 2;
                    ctx.beginPath();
                    ctx.arc(x, y, 10, 0, Math.PI * 2);
                    ctx.stroke();
                }
            }
        }
    }

    drawFCRadar() {
        if (!this.fcCtx) return;

        const ctx = this.fcCtx;
        const canvas = this.fcCanvas;
        const cx = canvas.width / 2;
        const cy = canvas.height / 2;
        const radius = Math.min(cx, cy) - 10;

        // Clear
        ctx.fillStyle = '#001a00';
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        // Draw range rings
        ctx.strokeStyle = '#003300';
        ctx.lineWidth = 1;
        for (let i = 1; i <= 4; i++) {
            ctx.beginPath();
            ctx.arc(cx, cy, radius * i / 4, 0, Math.PI * 2);
            ctx.stroke();
        }

        // Draw bearing lines
        for (let i = 0; i < 8; i++) {
            const angle = (i * 45 - 90) * Math.PI / 180;
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.lineTo(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius);
            ctx.stroke();
        }

        // Draw antenna beam indicator
        const fcState = this.state?.snr75 || this.state?.snr125 || this.state?.radar;
        if (fcState) {
            const antennaAz = fcState.antennaAz || 0;
            const beamWidth = 5; // degrees
            const beamAngle = (antennaAz - 90) * Math.PI / 180;
            const beamHalf = beamWidth / 2 * Math.PI / 180;

            ctx.fillStyle = 'rgba(0, 255, 0, 0.2)';
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.arc(cx, cy, radius, beamAngle - beamHalf, beamAngle + beamHalf);
            ctx.closePath();
            ctx.fill();

            // Beam center line
            ctx.strokeStyle = '#0f0';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.lineTo(cx + Math.cos(beamAngle) * radius, cy + Math.sin(beamAngle) * radius);
            ctx.stroke();
        }

        // Draw track if valid
        const track = this.state?.track;
        if (track && track.valid) {
            const range = track.range / 1000;
            if (range <= this.fcRange) {
                const normalizedRange = range / this.fcRange;
                const trackAngle = (track.azimuth - 90) * Math.PI / 180;
                const x = cx + Math.cos(trackAngle) * radius * normalizedRange;
                const y = cy + Math.sin(trackAngle) * radius * normalizedRange;

                // Draw track symbol
                ctx.fillStyle = '#0f0';
                ctx.beginPath();
                ctx.arc(x, y, 6, 0, Math.PI * 2);
                ctx.fill();

                // Draw track box
                ctx.strokeStyle = '#0f0';
                ctx.lineWidth = 2;
                ctx.strokeRect(x - 10, y - 10, 20, 20);
            }
        }

        // Range labels
        ctx.fillStyle = '#00ff00';
        ctx.font = '10px monospace';
        ctx.textAlign = 'center';
        for (let i = 1; i <= 4; i++) {
            const rangeKm = Math.round(this.fcRange * i / 4);
            ctx.fillText(`${rangeKm}`, cx + 5, cy - radius * i / 4 + 12);
        }
    }

    drawAScope() {
        if (!this.aScopeCtx) return;

        const ctx = this.aScopeCtx;
        const canvas = this.aScopeCanvas;
        const w = canvas.width;
        const h = canvas.height;

        // Clear
        ctx.fillStyle = '#001a00';
        ctx.fillRect(0, 0, w, h);

        // Grid
        ctx.strokeStyle = '#003300';
        ctx.lineWidth = 1;

        // Horizontal grid
        for (let i = 1; i < 4; i++) {
            ctx.beginPath();
            ctx.moveTo(0, h * i / 4);
            ctx.lineTo(w, h * i / 4);
            ctx.stroke();
        }

        // Vertical grid (range marks)
        for (let i = 1; i < 5; i++) {
            ctx.beginPath();
            ctx.moveTo(w * i / 5, 0);
            ctx.lineTo(w * i / 5, h);
            ctx.stroke();
        }

        // Baseline
        ctx.strokeStyle = '#004400';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(0, h - 10);
        ctx.lineTo(w, h - 10);
        ctx.stroke();

        // Draw target return if tracking
        const track = this.state?.track;
        if (track && track.valid) {
            const normalizedRange = (track.range / 1000) / this.fcRange;
            const x = normalizedRange * w;

            // Draw return pulse with noise
            ctx.strokeStyle = '#00ff00';
            ctx.lineWidth = 2;
            ctx.beginPath();

            for (let i = 0; i < w; i++) {
                const noise = Math.random() * 8 - 4;
                let signal = noise;

                // Add target return
                const distFromTarget = Math.abs(i - x);
                if (distFromTarget < 15) {
                    const strength = 40 * (1 - distFromTarget / 15);
                    signal += strength;
                }

                const y = h - 10 - Math.abs(signal);
                if (i === 0) {
                    ctx.moveTo(i, y);
                } else {
                    ctx.lineTo(i, y);
                }
            }
            ctx.stroke();

            // Range marker
            ctx.strokeStyle = '#ff0';
            ctx.lineWidth = 1;
            ctx.setLineDash([5, 5]);
            ctx.beginPath();
            ctx.moveTo(x, 0);
            ctx.lineTo(x, h);
            ctx.stroke();
            ctx.setLineDash([]);
        }
    }

    drawBScope() {
        if (!this.bScopeCtx) return;

        const ctx = this.bScopeCtx;
        const canvas = this.bScopeCanvas;
        const w = canvas.width;
        const h = canvas.height;

        // Clear
        ctx.fillStyle = '#001a00';
        ctx.fillRect(0, 0, w, h);

        // Grid
        ctx.strokeStyle = '#003300';
        ctx.lineWidth = 1;

        // Range lines (horizontal)
        for (let i = 1; i < 5; i++) {
            ctx.beginPath();
            ctx.moveTo(0, h * i / 5);
            ctx.lineTo(w, h * i / 5);
            ctx.stroke();
        }

        // Elevation lines (vertical)
        for (let i = 1; i < 5; i++) {
            ctx.beginPath();
            ctx.moveTo(w * i / 5, 0);
            ctx.lineTo(w * i / 5, h);
            ctx.stroke();
        }

        // Labels
        ctx.fillStyle = '#006600';
        ctx.font = '9px monospace';
        ctx.textAlign = 'right';
        ctx.fillText('0m', w - 2, h - 2);
        ctx.fillText(`${this.fcRange}km`, w - 2, 10);

        ctx.textAlign = 'left';
        ctx.fillText('0°', 2, h - 2);
        ctx.fillText('90°', 2, 10);

        // Draw target if tracking
        const track = this.state?.track;
        if (track && track.valid) {
            const normalizedRange = (track.range / 1000) / this.fcRange;
            const normalizedEl = (track.elevation || 0) / 90;

            const x = normalizedEl * w;
            const y = h - normalizedRange * h;

            // Draw target blip
            ctx.fillStyle = '#00ff00';
            ctx.beginPath();
            ctx.arc(x, y, 5, 0, Math.PI * 2);
            ctx.fill();

            // Draw crosshairs
            ctx.strokeStyle = '#00ff00';
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(x - 10, y);
            ctx.lineTo(x + 10, y);
            ctx.moveTo(x, y - 10);
            ctx.lineTo(x, y + 10);
            ctx.stroke();
        }
    }

    // Command methods
    sendCommand(cmd) {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify(cmd));
        }
    }

    sendPowerCommand(state) {
        const ewSystem = this.currentSystem === 'SA10' ? 'BIGBIRD' :
                        this.currentSystem === 'SA11' ? 'SNOWDRIFT' :
                        this.currentSystem === 'SA6' ? 'RADAR' :
                        this.currentSystem === 'SA3' ? 'P15' : 'P19';

        const fcSystem = this.currentSystem === 'SA10' ? 'FLAPLID' :
                        this.currentSystem === 'SA11' ? 'TELAR' :
                        this.currentSystem === 'SA6' ? 'RADAR' :
                        this.currentSystem === 'SA3' ? 'SNR125' : 'SNR75';

        this.sendCommand({ type: 'POWER', system: ewSystem, state: state });
        if (ewSystem !== fcSystem) {
            this.sendCommand({ type: 'POWER', system: fcSystem, state: state });
        }

        this.updateIndicator('indPower', state === 'ON');
    }

    sendEWModeCommand(mode) {
        const modeType = this.currentSystem === 'SA10' ? 'SURVEILLANCE_MODE' :
                        this.currentSystem === 'SA11' ? 'SNOWDRIFT_MODE' :
                        this.currentSystem === 'SA6' ? 'RADAR_MODE' :
                        this.currentSystem === 'SA3' ? 'P15_MODE' : 'P19_MODE';

        const modeNames = ['OFF', 'STANDBY', 'SEARCH', 'SECTOR'];
        this.sendCommand({ type: modeType, mode: modeNames[mode] || 'STANDBY' });
    }

    sendFCModeCommand(mode) {
        const modeType = this.currentSystem === 'SA3' ? 'SNR125_MODE' :
                        this.currentSystem === 'SA6' ? 'RADAR_MODE' : 'SNR75_MODE';

        const modeNames = ['OFF', 'STANDBY', 'ACQUISITION', 'TRACK', 'GUIDANCE'];
        this.sendCommand({ type: modeType, mode: modeNames[mode] || 'STANDBY' });
    }

    sendAntennaCommand() {
        const az = parseFloat(document.getElementById('fcAz')?.value) || 0;
        const el = parseFloat(document.getElementById('fcEl')?.value) || 5;
        this.sendCommand({ type: 'ANTENNA', azimuth: az, elevation: el });
    }

    selectTarget(targetId) {
        this.selectedTarget = targetId;
        this.updateTargetList();
    }

    designateTarget() {
        if (this.selectedTarget) {
            this.sendCommand({ type: 'DESIGNATE', targetId: this.selectedTarget });
            this.log(`Designated target #${this.selectedTarget}`, 'info');
        }
    }

    dropTrack() {
        this.sendCommand({ type: 'DROP_TRACK' });
        this.selectedTarget = null;
    }

    launchMissile() {
        this.sendCommand({ type: 'LAUNCH' });
    }

    // UI helpers
    updateConnectionStatus(connected) {
        const statusEl = document.getElementById('connectionStatus');
        const wsStatusEl = document.getElementById('wsStatus');

        if (statusEl) {
            const dot = statusEl.querySelector('.status-dot');
            const text = statusEl.querySelector('.status-text');

            dot?.classList.toggle('connected', connected);
            dot?.classList.toggle('disconnected', !connected);
            if (text) text.textContent = connected ? 'Connected' : 'Disconnected';
        }

        if (wsStatusEl) {
            wsStatusEl.textContent = connected ? 'Connected' : 'Disconnected';
        }
    }

    updateRate() {
        const now = Date.now();
        const elapsed = (now - this.lastUpdateTime) / 1000;

        if (elapsed >= 1) {
            const rate = this.updateCount / elapsed;
            document.getElementById('updateRate').textContent = `${rate.toFixed(1)} Hz`;
            document.getElementById('lastUpdate').textContent = new Date().toLocaleTimeString();
            this.updateCount = 0;
            this.lastUpdateTime = now;
        }
    }

    log(message, type = 'info') {
        const logEl = document.getElementById('eventLog');
        if (!logEl) return;

        const entry = document.createElement('div');
        entry.className = `log-entry log-${type}`;
        entry.innerHTML = `<span class="log-time">${new Date().toLocaleTimeString()}</span> ${message}`;

        logEl.insertBefore(entry, logEl.firstChild);

        // Keep only last 50 entries
        while (logEl.children.length > 50) {
            logEl.removeChild(logEl.lastChild);
        }
    }

    showInitSiteModal() {
        document.getElementById('initSiteModal').style.display = 'flex';
    }

    hideInitSiteModal() {
        document.getElementById('initSiteModal').style.display = 'none';
    }

    initializeSite() {
        const systemType = document.getElementById('modalSystemSelect')?.value;
        const siteId = document.getElementById('newSiteId')?.value;
        const groupName = document.getElementById('groupName')?.value;

        if (siteId && systemType) {
            this.sendCommand({
                type: 'CREATE_SITE',
                siteId: siteId,
                systemType: systemType,
                name: groupName || siteId
            });
            this.hideInitSiteModal();
            this.log(`Initializing ${systemType} site: ${siteId}`, 'info');
        }
    }
}

// Initialize on page load
window.addEventListener('DOMContentLoaded', () => {
    window.samSim = new SAMSimClient();
});
