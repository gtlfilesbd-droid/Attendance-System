/**
 * MapTracking - Live employee tracking and route playback
 * Uses Leaflet.js + OpenStreetMap. Integrates with Django dashboard templates.
 */
class MapTracking {
    constructor() {
        this.map = null;
        this.markers = {};
        this.routePolyline = null;
        this.routeMarkers = [];
        this.playbackMarker = null;
        this.playbackInterval = null;
        this.playbackIndex = 0;
        this.playbackLocations = [];
        this.isPlaying = false;
        this.playbackSpeed = 2;
        this.autoRefreshInterval = null;
        this.onProgressUpdate = null;
        this.onLocationChange = null;
        this.onPlaybackComplete = null;
        this._panAnimationId = null;
        this._baseTileLayer = null;
    }

    /**
     * Get base API URL (same origin)
     */
    getApiBase() {
        return window.location.origin;
    }

    /**
     * Get auth headers for Django session (CSRF + cookies)
     */
    getAuthHeaders() {
        const csrf = this.getCSRFToken();
        return {
            'X-CSRFToken': csrf,
            'Content-Type': 'application/json'
        };
    }

    getCSRFToken() {
        const cookies = document.cookie.split(';');
        for (let cookie of cookies) {
            const parts = cookie.trim().split('=');
            const name = parts[0];
            const value = parts.slice(1).join('=').trim();
            if (name === 'csrftoken') return value;
        }
        const meta = document.querySelector('meta[name=csrf-token]');
        return meta ? meta.getAttribute('content') : '';
    }

    // --- Live map ---

    /**
     * Build a Leaflet TileLayer subclass that sets referrerpolicy="origin" on
     * every tile <img> element.  This is the only reliable way to force the
     * browser to include the Referer/Origin header with cross-origin tile
     * requests — Leaflet's standard L.tileLayer options have no referrerPolicy
     * support, so we must override createTile().
     */
    _makeReferrerTileLayer(url, options) {
        const ReferrerTileLayer = L.TileLayer.extend({
            createTile(coords, done) {
                const img = L.TileLayer.prototype.createTile.call(this, coords, done);
                img.referrerPolicy = 'origin';
                return img;
            },
        });
        return new ReferrerTileLayer(url, options);
    }

    /**
     * Create a resilient base tile layer.
     * Primary  : OpenStreetMap (with referrerpolicy="origin" on every tile img)
     * Fallback : CARTO basemaps (identical referrer fix)
     *
     * OSM volunteer servers require the Referer header.  Django's
     * SecurityMiddleware defaults to Referrer-Policy: same-origin, which strips
     * the header on cross-origin requests.  Setting referrerpolicy on the img
     * element overrides the document policy for that individual request.
     */
    createBaseTileLayer() {
        const osmUrl  = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
        const osmAttr = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';

        const cartoUrl  = 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
        const cartoAttr = osmAttr + ' &copy; <a href="https://carto.com/attributions">CARTO</a>';

        const layer = this._makeReferrerTileLayer(osmUrl, {
            attribution: osmAttr,
            maxZoom: 19,
        });

        let tileErrorCount = 0;
        let hasFallenBack  = false;
        layer.on('tileerror', () => {
            tileErrorCount += 1;
            if (!hasFallenBack && tileErrorCount >= 3) {
                hasFallenBack = true;
                try {
                    if (this.map) {
                        this.map.removeLayer(layer);
                        const fb = this._makeReferrerTileLayer(cartoUrl, {
                            subdomains: 'abcd',
                            attribution: cartoAttr,
                            maxZoom: 19,
                        });
                        fb.addTo(this.map);
                        this._baseTileLayer = fb;
                    }
                } catch (e) {
                    console.warn('Map tile fallback failed:', e);
                }
            }
        });

        return layer;
    }

    /**
     * Initialize Leaflet map for live tracking (OpenStreetMap tiles)
     * @param {string} mapElementId - ID of the map container element
     * @param {object} options - Optional map options (center, zoom)
     * @returns {Promise<void>}
     */
    async initLiveMap(mapElementId, options = {}) {
        const el = document.getElementById(mapElementId);
        if (!el) throw new Error('Map element not found: ' + mapElementId);
        const center = options.center || [23.8103, 90.4125];
        const zoom = options.zoom || 12;
        this.map = L.map(mapElementId).setView(center, zoom);
        this._baseTileLayer = this.createBaseTileLayer();
        this._baseTileLayer.addTo(this.map);
        this.markers = {};
        return Promise.resolve();
    }

    /**
     * Fetch live locations from API (GET /api/tracking/live-locations/)
     * @returns {Promise<Array>} Array of location objects
     */
    async fetchLiveLocations() {
        const url = this.getApiBase() + '/api/tracking/live-locations/';
        const response = await fetch(url, {
            method: 'GET',
            headers: this.getAuthHeaders(),
            credentials: 'same-origin'
        });
        if (!response.ok) {
            if (response.status === 403) throw new Error('Access denied. Admin only.');
            throw new Error('Failed to load locations: ' + response.status);
        }
        const json = await response.json();
        if (!json.success || !json.data) throw new Error('Invalid response');
        return json.data.locations || [];
    }

    /**
     * Get marker color by minutes since update (0-5 green, 5-10 blue, 10-15 orange, 15+ red)
     */
    getMarkerColor(location) {
        const minutes = location.minutes_ago;
        if (minutes === undefined) {
            const ts = location.timestamp ? new Date(location.timestamp) : null;
            if (!ts) return '#10b981';
            const minutesAgo = (Date.now() - ts.getTime()) / 60000;
            if (minutesAgo <= 5) return '#10b981';
            if (minutesAgo <= 10) return '#2563eb';
            if (minutesAgo <= 15) return '#f59e0b';
            return '#ef4444';
        }
        if (minutes <= 5) return '#10b981';
        if (minutes <= 10) return '#2563eb';
        if (minutes <= 15) return '#f59e0b';
        return '#ef4444';
    }

    /**
     * Create a div icon for a marker (SVG map-pin / teardrop, color + optional label)
     * Size 32x40px, anchor at tip of pin. Same status colors (green/blue/orange/red).
     */
    createMarkerIcon(color, label = '') {
        const pinPath = 'M16 2 C26 2 32 10 32 18 C32 26 16 40 16 40 C16 40 0 26 0 18 C0 10 6 2 16 2 Z';
        const labelText = label
            ? `<text x="16" y="16" text-anchor="middle" dominant-baseline="middle" fill="#fff" font-size="12" font-weight="bold" font-family="system-ui,sans-serif">${label}</text>`
            : '';
        const html = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 40" width="32" height="40" style="filter:drop-shadow(0 1px 3px rgba(0,0,0,0.35));">
            <path d="${pinPath}" fill="${color}" stroke="#fff" stroke-width="2"/>
            ${labelText}
        </svg>`;
        return L.divIcon({
            html,
            className: 'custom-marker',
            iconSize: [32, 40],
            iconAnchor: [16, 40]
        });
    }

    /**
     * Update map markers from locations array (one per employee)
     */
    updateMapMarkers(locations) {
        if (!this.map) return;
        const newIds = new Set();
        (locations || []).forEach(loc => {
            const id = loc.employee_id || loc.employee_code || ('loc_' + (loc.latitude + ',' + loc.longitude));
            newIds.add(id);
            const lat = loc.latitude != null ? loc.latitude : (loc.location && loc.location.lat);
            const lng = loc.longitude != null ? loc.longitude : (loc.location && loc.location.lng);
            if (lat == null || lng == null) return;
            const latLng = [parseFloat(lat), parseFloat(lng)];
            const color = this.getMarkerColor(loc);
            const icon = this.createMarkerIcon(color);
            if (this.markers[id]) {
                this.markers[id].setLatLng(latLng);
                this.markers[id].setIcon(icon);
                this.markers[id].setPopupContent(this.buildPopupContent(loc));
            } else {
                const marker = L.marker(latLng, { icon }).addTo(this.map);
                marker.bindPopup(this.buildPopupContent(loc));
                this.markers[id] = marker;
            }
        });
        Object.keys(this.markers).forEach(id => {
            if (!newIds.has(id)) {
                this.map.removeLayer(this.markers[id]);
                delete this.markers[id];
            }
        });
        if (locations && locations.length > 0) {
            const bounds = L.latLngBounds(locations.map(loc => {
                const lat = loc.latitude != null ? loc.latitude : (loc.location && loc.location.lat);
                const lng = loc.longitude != null ? loc.longitude : (loc.location && loc.location.lng);
                return [parseFloat(lat), parseFloat(lng)];
            }).filter(x => x[0] != null && x[1] != null));
            if (bounds.isValid()) this.map.fitBounds(bounds, { padding: [30, 30], maxZoom: 15 });
        }
    }

    buildPopupContent(loc) {
        const name = loc.employee_name || 'Unknown';
        const code = loc.employee_code || loc.employee_id || '';
        const hasAddress = loc.address && String(loc.address).trim();
        const locationText = hasAddress
            ? loc.address
            : (() => {
                const lat = loc.latitude != null ? loc.latitude : (loc.location && loc.location.lat);
                const lng = loc.longitude != null ? loc.longitude : (loc.location && loc.location.lng);
                if (lat != null && lng != null) return parseFloat(lat).toFixed(5) + ', ' + parseFloat(lng).toFixed(5);
                return '—';
            })();
        const profileUrl = loc.profile_picture_url || null;
        const initial = (name && String(name).trim()) ? String(name).trim().charAt(0).toUpperCase() : '?';
        const timeAgo = this.formatTimestamp(loc.timestamp);
        const speedKmh = (loc.speed != null && !isNaN(loc.speed)) ? (parseFloat(loc.speed) * 3.6).toFixed(1) + ' km/h' : null;
        const speedVal = speedKmh ? ('Device: ' + speedKmh) : '—';
        const batteryVal = (loc.battery_level != null && !isNaN(loc.battery_level)) ? loc.battery_level + '%' : '—';
        const batteryLevel = (loc.battery_level != null && !isNaN(loc.battery_level)) ? parseInt(loc.battery_level, 10) : 0;
        const batteryIcon = batteryLevel >= 66 ? 'fa-battery-full' : batteryLevel >= 33 ? 'fa-battery-half' : batteryLevel > 0 ? 'fa-battery-quarter' : 'fa-battery-empty';
        const iconStyle = 'color:#64748b;width:1em;margin-right:6px;';
        const avatarFallbackStyle = 'width:40px;height:40px;border-radius:50%;background:linear-gradient(135deg,#2563eb,#1d4ed8);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:1rem;flex-shrink:0;';
        const avatarHtml = profileUrl
            ? `<span style="display:inline-block;width:40px;height:40px;position:relative;flex-shrink:0;"><img src="${profileUrl.replace(/"/g, '&quot;')}" alt="" style="position:absolute;top:0;left:0;width:40px;height:40px;border-radius:50%;object-fit:cover;" onerror="this.style.visibility='hidden';this.nextElementSibling.style.visibility='visible';" /><span style="position:absolute;top:0;left:0;visibility:hidden;${avatarFallbackStyle}">${initial}</span></span>`
            : `<div style="${avatarFallbackStyle}">${initial}</div>`;
        return `<div style="font-family:system-ui,sans-serif;min-width:200px;max-width:220px;padding:12px 14px;border-radius:10px;border:1px solid #e2e8f0;box-shadow:0 4px 12px rgba(0,0,0,0.08);background:#fff;">
            <div style="display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:8px;">
                <div style="min-width:0;flex:1;">
                    <div style="font-weight:700;font-size:1rem;color:#1e293b;word-wrap:break-word;">${name}</div>
                    <div style="font-size:0.8rem;color:#64748b;line-height:1.5;margin-top:2px;">
                        <i class="fas fa-id-badge fa-fw" style="${iconStyle}"></i>${code || '—'}
                    </div>
                </div>
                <div style="position:relative;flex-shrink:0;">${avatarHtml}</div>
            </div>
            <div style="font-size:0.8rem;color:#475569;line-height:1.5;margin:6px 0 2px 0;display:flex;align-items:flex-start;gap:6px;">
                <i class="fas fa-map-marker-alt fa-fw" style="${iconStyle};flex-shrink:0;"></i>
                <div style="max-height:60px;overflow-y:auto;overflow-x:hidden;word-break:break-word;overflow-wrap:break-word;-webkit-overflow-scrolling:touch;min-width:0;flex:1;">${locationText}</div>
            </div>
            <div style="font-size:0.8rem;color:#475569;line-height:1.5;margin:6px 0 2px 0;">
                <i class="fas fa-circle fa-fw" style="color:#10b981;font-size:0.5em;vertical-align:middle;margin-right:4px;"></i><span style="color:#10b981;font-weight:600;">Active</span> <span style="color:#64748b;">•</span> <i class="fas fa-clock fa-fw" style="${iconStyle}"></i>${timeAgo}
            </div>
            <div style="font-size:0.8rem;color:#475569;line-height:1.5;margin:6px 0 2px 0;">
                <i class="fas fa-tachometer-alt fa-fw" style="${iconStyle}"></i>${speedVal}
            </div>
            <div style="font-size:0.8rem;color:#475569;line-height:1.5;margin:6px 0 0 0;">
                <i class="fas ${batteryIcon} fa-fw" style="${iconStyle}"></i>${batteryVal}
            </div>
        </div>`;
    }

    /**
     * Start auto-refresh: poll live locations every intervalMs and call callback(locations)
     */
    startAutoRefresh(intervalMs, callback) {
        this.stopAutoRefresh();
        this.autoRefreshInterval = setInterval(async () => {
            try {
                const locations = await this.fetchLiveLocations();
                this.updateMapMarkers(locations);
                if (typeof callback === 'function') callback(locations);
            } catch (e) {
                console.error('Auto-refresh error:', e);
            }
        }, intervalMs);
    }

    stopAutoRefresh() {
        if (this.autoRefreshInterval) {
            clearInterval(this.autoRefreshInterval);
            this.autoRefreshInterval = null;
        }
    }

    /**
     * Format timestamp for display ("Just now", "5m ago", "2h ago")
     */
    formatTimestamp(timestamp) {
        if (!timestamp) return '—';
        const date = new Date(timestamp);
        const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
        if (seconds < 60) return 'Just now';
        const minutes = Math.floor(seconds / 60);
        if (minutes < 60) return minutes + 'm ago';
        const hours = Math.floor(minutes / 60);
        if (hours < 24) return hours + 'h ago';
        const days = Math.floor(hours / 24);
        return days + 'd ago';
    }

    // --- Route map ---

    /**
     * Initialize Leaflet map for route history
     */
    async initRouteMap(mapElementId, options = {}) {
        const el = document.getElementById(mapElementId);
        if (!el) throw new Error('Map element not found: ' + mapElementId);
        const center = options.center || [23.8103, 90.4125];
        const zoom = options.zoom || 12;
        this.map = L.map(mapElementId).setView(center, zoom);
        this._baseTileLayer = this.createBaseTileLayer();
        this._baseTileLayer.addTo(this.map);
        this.routePolyline = null;
        this.routeMarkers = [];
        return Promise.resolve();
    }

    /**
     * Fetch employee route from API
     * @param {string} employeeId
     * @param {string} date - YYYY-MM-DD
     * @param {string|null} startTime - HH:MM or HH:MM:SS
     * @param {string|null} endTime - HH:MM or HH:MM:SS
     * @returns {Promise<{locations: Array, total_distance_km?: number}>}
     */
    async fetchEmployeeRoute(employeeId, date, startTime, endTime) {
        const params = new URLSearchParams({ employee_id: employeeId });
        if (date) params.set('date', date);
        if (startTime) params.set('start_time', startTime.length === 5 ? startTime + ':00' : startTime);
        if (endTime) params.set('end_time', endTime.length === 5 ? endTime + ':00' : endTime);
        const url = this.getApiBase() + '/api/tracking/employee-route/?' + params.toString();
        const response = await fetch(url, {
            method: 'GET',
            headers: this.getAuthHeaders(),
            credentials: 'same-origin'
        });
        if (!response.ok) throw new Error('Failed to load route: ' + response.status);
        const json = await response.json();
        if (!json.success || !json.data) throw new Error('Invalid response');
        return json.data;
    }

    /**
     * Smooth polyline with Catmull-Rom spline for better visual (reduces zigzag).
     * @param {Array<[number,number]>} latLngs - Array of [lat, lng]
     * @param {number} pointsPerSegment - Interpolated points between each pair (default 4)
     * @returns {Array<[number,number]>} Smoothed points
     */
    smoothPolyline(latLngs, pointsPerSegment = 4) {
        if (!latLngs || latLngs.length < 3) return latLngs;
        const out = [[latLngs[0][0], latLngs[0][1]]];
        const n = latLngs.length;
        for (let i = 0; i < n - 1; i++) {
            const p0 = latLngs[Math.max(0, i - 1)];
            const p1 = latLngs[i];
            const p2 = latLngs[i + 1];
            const p3 = latLngs[Math.min(n - 1, i + 2)];
            const step = 1 / (pointsPerSegment + 1);
            const kEnd = (i === n - 2) ? (pointsPerSegment + 1) : pointsPerSegment;
            for (let k = 1; k <= kEnd; k++) {
                const t = (k === pointsPerSegment + 1 && i === n - 2) ? 1 : k * step;
                const t2 = t * t;
                const t3 = t2 * t;
                const lat = 0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3);
                const lng = 0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3);
                out.push([lat, lng]);
            }
        }
        return out;
    }

    /**
     * Draw route polyline on map (with Catmull-Rom smoothing to reduce zigzag)
     */
    drawRoute(locations) {
        if (!this.map || !locations || locations.length === 0) return;
        if (this.routePolyline) {
            this.map.removeLayer(this.routePolyline);
            this.routePolyline = null;
        }
        const latLngs = locations.map(loc => {
            const lat = loc.latitude != null ? loc.latitude : (loc.location && loc.location.lat);
            const lng = loc.longitude != null ? loc.longitude : (loc.location && loc.location.lng);
            return [parseFloat(lat), parseFloat(lng)];
        }).filter(x => x[0] != null && x[1] != null);
        if (latLngs.length < 2) return;
        const smoothed = latLngs.length >= 3 ? this.smoothPolyline(latLngs, 4) : latLngs;
        this.routePolyline = L.polyline(smoothed, { color: '#2563eb', opacity: 0.8, weight: 5 }).addTo(this.map);
        this.map.fitBounds(this.routePolyline.getBounds(), { padding: [30, 30], maxZoom: 15 });
    }

    /**
     * Add start (green S) and end (red E) markers for route
     */
    addRouteMarkers(locations) {
        if (!this.map || !locations || locations.length === 0) return;
        this.routeMarkers.forEach(m => this.map.removeLayer(m));
        this.routeMarkers = [];
        const first = locations[0];
        const last = locations[locations.length - 1];
        const toLatLng = (loc) => {
            const lat = loc.latitude != null ? loc.latitude : (loc.location && loc.location.lat);
            const lng = loc.longitude != null ? loc.longitude : (loc.location && loc.location.lng);
            return [parseFloat(lat), parseFloat(lng)];
        };
        const startIcon = this.createMarkerIcon('#10b981', 'S');
        const endIcon = this.createMarkerIcon('#ef4444', 'E');
        this.routeMarkers.push(L.marker(toLatLng(first), { icon: startIcon }).addTo(this.map).bindPopup('Start'));
        if (first !== last) this.routeMarkers.push(L.marker(toLatLng(last), { icon: endIcon }).addTo(this.map).bindPopup('End'));
    }

    /**
     * Playback route: animate a marker along the route
     */
    playbackRoute(locations, options = {}) {
        if (!this.map || !locations || locations.length === 0) return;
        this.stopPlayback();
        this.playbackLocations = locations;
        this.playbackSpeed = options.speed != null ? options.speed : this.playbackSpeed;
        this.playbackIndex = 0;
        if (this.playbackMarker) this.map.removeLayer(this.playbackMarker);
        const first = locations[0];
        const lat = first.latitude != null ? first.latitude : (first.location && first.location.lat);
        const lng = first.longitude != null ? first.longitude : (first.location && first.location.lng);
        const icon = this.createMarkerIcon('#2563eb', '');
        this.playbackMarker = L.marker([parseFloat(lat), parseFloat(lng)], { icon }).addTo(this.map);
        this.isPlaying = true;
        this.tickPlayback();
    }

    tickPlayback() {
        if (!this.isPlaying || !this.playbackLocations.length) return;
        if (this.onProgressUpdate) this.onProgressUpdate(this.playbackIndex + 1, this.playbackLocations.length);
        if (this.onLocationChange) this.onLocationChange(this.playbackIndex, this.playbackLocations[this.playbackIndex]);
        const loc = this.playbackLocations[this.playbackIndex];
        const lat = loc.latitude != null ? loc.latitude : (loc.location && loc.location.lat);
        const lng = loc.longitude != null ? loc.longitude : (loc.location && loc.location.lng);
        this.playbackMarker.setLatLng([parseFloat(lat), parseFloat(lng)]);
        const delay = Math.max(100, 500 / this.playbackSpeed);
        if (this._panAnimationId != null) cancelAnimationFrame(this._panAnimationId);
        if (this.map && lat != null && lng != null) {
            const startCenter = this.map.getCenter();
            const targetLat = parseFloat(lat);
            const targetLng = parseFloat(lng);
            const startTime = performance.now();
            const duration = delay;
            const step = () => {
                const elapsed = performance.now() - startTime;
                const progress = Math.min(1, elapsed / duration);
                const eased = 1 - (1 - progress) * (1 - progress);
                const newLat = startCenter.lat + (targetLat - startCenter.lat) * eased;
                const newLng = startCenter.lng + (targetLng - startCenter.lng) * eased;
                this.map.setView([newLat, newLng], this.map.getZoom());
                if (progress < 1 && this.isPlaying) {
                    this._panAnimationId = requestAnimationFrame(step);
                } else {
                    this._panAnimationId = null;
                }
            };
            this._panAnimationId = requestAnimationFrame(step);
        }
        this.playbackIndex++;
        if (this.playbackIndex >= this.playbackLocations.length) {
            this.isPlaying = false;
            if (this.onPlaybackComplete) this.onPlaybackComplete();
            return;
        }
        this.playbackInterval = setTimeout(() => this.tickPlayback(), delay);
    }

    startPlayback() {
        if (!this.playbackLocations.length) return;
        this.isPlaying = true;
        this.tickPlayback();
    }

    pausePlayback() {
        this.isPlaying = false;
        if (this._panAnimationId != null) {
            cancelAnimationFrame(this._panAnimationId);
            this._panAnimationId = null;
        }
        if (this.playbackInterval) {
            clearTimeout(this.playbackInterval);
            this.playbackInterval = null;
        }
    }

    stopPlayback() {
        if (this._panAnimationId != null) {
            cancelAnimationFrame(this._panAnimationId);
            this._panAnimationId = null;
        }
        this.pausePlayback();
        this.playbackIndex = 0;
        if (this.playbackMarker && this.playbackLocations.length > 0) {
            const first = this.playbackLocations[0];
            const lat = first.latitude != null ? first.latitude : (first.location && first.location.lat);
            const lng = first.longitude != null ? first.longitude : (first.location && first.location.lng);
            this.playbackMarker.setLatLng([parseFloat(lat), parseFloat(lng)]);
        }
        if (this.onProgressUpdate) this.onProgressUpdate(0, this.playbackLocations.length);
        if (this.onLocationChange) this.onLocationChange(0, this.playbackLocations[0]);
    }

    jumpToLocation(index) {
        if (!this.playbackLocations.length || index < 0 || index >= this.playbackLocations.length) return;
        this.playbackIndex = index;
        const loc = this.playbackLocations[index];
        const lat = loc.latitude != null ? loc.latitude : (loc.location && loc.location.lat);
        const lng = loc.longitude != null ? loc.longitude : (loc.location && loc.location.lng);
        if (this.playbackMarker) this.playbackMarker.setLatLng([parseFloat(lat), parseFloat(lng)]);
        if (this.onProgressUpdate) this.onProgressUpdate(index + 1, this.playbackLocations.length);
        if (this.onLocationChange) this.onLocationChange(index, loc);
    }

    setPlaybackSpeed(speed) {
        this.playbackSpeed = speed;
    }

    // --- Loading & alerts ---

    showLoading(elementId) {
        const el = document.getElementById(elementId);
        if (!el) return;
        el.innerHTML = '<div class="text-center py-4"><div class="spinner-border text-primary" role="status"><span class="visually-hidden">Loading...</span></div><p class="mt-2 text-muted">Loading...</p></div>';
    }

    hideLoading(elementId, content) {
        const el = document.getElementById(elementId);
        if (!el) return;
        el.innerHTML = content || '';
    }

    showAlert(message, type) {
        type = type || 'info';
        const alertDiv = document.createElement('div');
        alertDiv.className = 'alert alert-' + type + ' alert-dismissible fade show position-fixed';
        alertDiv.style.cssText = 'top: 1rem; left: 50%; transform: translateX(-50%); z-index: 9999; min-width: 280px;';
        alertDiv.innerHTML = message + '<button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>';
        document.body.appendChild(alertDiv);
        setTimeout(() => { if (alertDiv.parentNode) alertDiv.remove(); }, 5000);
    }
}
