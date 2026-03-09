/**
 * MapTracking - Live employee tracking and route playback
 * Uses Leaflet.js + OpenStreetMap
 */
class MapTracking {
    constructor() {
        this.map = null;
        this.markers = {};
        this.routePolyline = null;
        this.routeMarkers = [];
        this.playbackTimer = null;
        this.isPlaying = false;
        this.playbackSpeed = 1;
        this.currentPlaybackIndex = 0;
        this.autoRefreshTimer = null;
    }

    // ─── Map Initialization ───────────────────────────────────────────────────

    async initLiveMap(containerId) {
        try {
            if (typeof L === 'undefined') {
                throw new Error('Leaflet.js is not loaded');
            }
            this.map = L.map(containerId, {
                center: [23.8103, 90.4125],
                zoom: 12,
                zoomControl: true
            });
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                maxZoom: 19,
                attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            }).addTo(this.map);
            return this.map;
        } catch (e) {
            console.error('Error initializing live map:', e);
            const container = document.getElementById(containerId);
            if (container) {
                container.innerHTML = '<div class="alert alert-danger m-3">Error initializing map. Please check if Leaflet.js is loaded.</div>';
            }
            throw e;
        }
    }

    async initRouteMap(containerId) {
        try {
            if (typeof L === 'undefined') {
                throw new Error('Leaflet.js is not loaded');
            }
            this.map = L.map(containerId, {
                center: [23.8103, 90.4125],
                zoom: 13,
                zoomControl: true
            });
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                maxZoom: 19,
                attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            }).addTo(this.map);
            return this.map;
        } catch (e) {
            console.error('Error initializing route map:', e);
            const container = document.getElementById(containerId);
            if (container) {
                container.innerHTML = '<div class="alert alert-danger m-3">Error initializing map. Please check if Leaflet.js is loaded.</div>';
            }
            throw e;
        }
    }

    // ─── Live Tracking API ────────────────────────────────────────────────────

    async fetchLiveLocations() {
        try {
            const resp = await fetch('/api/tracking/live-locations/', {
                headers: {
                    'X-CSRFToken': this._getCSRFToken(),
                    'Content-Type': 'application/json'
                }
            });
            if (!resp.ok) throw new Error('API error ' + resp.status);
            const json = await resp.json();
            // Response format: { success: true, data: { locations: [...] } }
            if (json && json.data && Array.isArray(json.data.locations)) {
                return json.data.locations;
            }
            // Fallback: if it's already an array
            if (Array.isArray(json)) return json;
            return [];
        } catch (e) {
            console.error('fetchLiveLocations error:', e);
            return [];
        }
    }

    startAutoRefresh(intervalMs, callback) {
        if (this.autoRefreshTimer) clearInterval(this.autoRefreshTimer);
        const run = async () => {
            try {
                const locations = await this.fetchLiveLocations();
                if (callback) callback(locations);
            } catch (e) {
                console.error('Auto-refresh error:', e);
            }
        };
        run();
        this.autoRefreshTimer = setInterval(run, intervalMs);
    }

    stopAutoRefresh() {
        if (this.autoRefreshTimer) {
            clearInterval(this.autoRefreshTimer);
            this.autoRefreshTimer = null;
        }
    }

    updateMapMarkers(locations) {
        if (!this.map) return;

        const seen = new Set();

        (locations || []).forEach(loc => {
            const lat = parseFloat(loc.latitude);
            const lng = parseFloat(loc.longitude);
            if (isNaN(lat) || isNaN(lng)) return;

            const id = String(loc.employee_id || loc.id || '');
            if (!id) return;
            seen.add(id);

            const initials = this._getInitials(loc.employee_name || loc.name || '?');
            const color = this._employeeColor(id);
            const icon = this._createEmployeeIcon(initials, color);

            if (this.markers[id]) {
                this.markers[id].setLatLng([lat, lng]);
                this.markers[id].setIcon(icon);
                if (this.markers[id].getPopup()) {
                    this.markers[id].getPopup().setContent(this._buildPopupContent(loc));
                }
            } else {
                const marker = L.marker([lat, lng], { icon })
                    .bindPopup(this._buildPopupContent(loc));
                marker.addTo(this.map);
                this.markers[id] = marker;
            }
        });

        // Remove markers no longer in the feed
        Object.keys(this.markers).forEach(id => {
            if (!seen.has(id)) {
                this.map.removeLayer(this.markers[id]);
                delete this.markers[id];
            }
        });
    }

    // ─── Route History API ────────────────────────────────────────────────────

    async fetchEmployeeRoute(employeeId, date, startTime, endTime) {
        try {
            let url = `/api/tracking/employee-route/?employee_id=${encodeURIComponent(employeeId)}&date=${encodeURIComponent(date)}`;
            if (startTime) url += `&start_time=${encodeURIComponent(startTime)}`;
            if (endTime) url += `&end_time=${encodeURIComponent(endTime)}`;

            const resp = await fetch(url, {
                headers: {
                    'X-CSRFToken': this._getCSRFToken(),
                    'Content-Type': 'application/json'
                }
            });
            if (!resp.ok) throw new Error('API error ' + resp.status);
            const json = await resp.json();
            // Response format: { success: true, data: { locations: [...], total_distance_km: ..., ... } }
            if (json && json.data) {
                return json.data;
            }
            return json;
        } catch (e) {
            console.error('fetchEmployeeRoute error:', e);
            throw e;
        }
    }

    // ─── Route Drawing ────────────────────────────────────────────────────────

    drawRoute(locations) {
        if (!this.map || !locations || locations.length === 0) return;

        // Clear existing route
        this._clearRoutePolyline();

        const latLngs = locations
            .map(loc => {
                const lat = parseFloat(loc.latitude);
                const lng = parseFloat(loc.longitude);
                return isNaN(lat) || isNaN(lng) ? null : [lat, lng];
            })
            .filter(Boolean);

        if (latLngs.length === 0) return;

        this.routePolyline = L.polyline(latLngs, {
            color: '#2563eb',
            weight: 4,
            opacity: 0.85,
            lineJoin: 'round',
            lineCap: 'round'
        }).addTo(this.map);

        this.map.fitBounds(this.routePolyline.getBounds(), { padding: [40, 40] });
    }

    addRouteMarkers(locations) {
        if (!this.map || !locations || locations.length === 0) return;

        // Remove old route markers
        this.routeMarkers.forEach(m => { if (this.map) this.map.removeLayer(m); });
        this.routeMarkers = [];

        const first = locations[0];
        const last = locations[locations.length - 1];

        const startIcon = L.divIcon({
            className: '',
            html: '<div style="background:#10b981;color:#fff;border-radius:50%;width:28px;height:28px;display:flex;align-items:center;justify-content:center;font-size:12px;box-shadow:0 2px 6px rgba(0,0,0,0.3);border:2px solid #fff"><i class="fas fa-play"></i></div>',
            iconSize: [28, 28],
            iconAnchor: [14, 14]
        });
        const endIcon = L.divIcon({
            className: '',
            html: '<div style="background:#ef4444;color:#fff;border-radius:50%;width:28px;height:28px;display:flex;align-items:center;justify-content:center;font-size:12px;box-shadow:0 2px 6px rgba(0,0,0,0.3);border:2px solid #fff"><i class="fas fa-flag-checkered"></i></div>',
            iconSize: [28, 28],
            iconAnchor: [14, 14]
        });

        const startLat = parseFloat(first.latitude);
        const startLng = parseFloat(first.longitude);
        const endLat = parseFloat(last.latitude);
        const endLng = parseFloat(last.longitude);

        if (!isNaN(startLat) && !isNaN(startLng)) {
            const sm = L.marker([startLat, startLng], { icon: startIcon })
                .bindPopup('<b>Start</b><br>' + this.formatTimestamp(first.timestamp || first.created_at));
            sm.addTo(this.map);
            this.routeMarkers.push(sm);
        }

        if (!isNaN(endLat) && !isNaN(endLng)) {
            const em = L.marker([endLat, endLng], { icon: endIcon })
                .bindPopup('<b>End</b><br>' + this.formatTimestamp(last.timestamp || last.created_at));
            em.addTo(this.map);
            this.routeMarkers.push(em);
        }
    }

    // ─── Playback ─────────────────────────────────────────────────────────────

    playbackRoute(locations, options) {
        if (!locations || locations.length === 0) return;

        if (this.isPlaying) {
            this.stopPlayback();
            return;
        }

        const speed = (options && options.speed) ? options.speed : this.playbackSpeed;
        const intervalMs = Math.max(100, 1000 / speed);

        if (this.currentPlaybackIndex >= locations.length) {
            this.currentPlaybackIndex = 0;
        }

        this.isPlaying = true;

        this.playbackTimer = setInterval(() => {
            if (this.currentPlaybackIndex >= locations.length) {
                this.stopPlayback();
                return;
            }

            const loc = locations[this.currentPlaybackIndex];
            const lat = parseFloat(loc.latitude);
            const lng = parseFloat(loc.longitude);

            if (!isNaN(lat) && !isNaN(lng) && this.map) {
                this.map.panTo([lat, lng], { animate: true, duration: 0.5 });
            }

            if (typeof updateProgress === 'function') {
                updateProgress(this.currentPlaybackIndex + 1, locations.length);
            }
            if (typeof highlightTimelineItem === 'function') {
                highlightTimelineItem(this.currentPlaybackIndex);
            }

            this.currentPlaybackIndex++;
        }, intervalMs);
    }

    stopPlayback() {
        if (this.playbackTimer) {
            clearInterval(this.playbackTimer);
            this.playbackTimer = null;
        }
        this.isPlaying = false;
    }

    setPlaybackSpeed(speed) {
        this.playbackSpeed = speed;
        if (this.isPlaying) {
            this.stopPlayback();
        }
    }

    jumpToLocation(index) {
        if (!this.map || (index === null && index !== 0)) return;
        this.currentPlaybackIndex = index;
        if (typeof highlightTimelineItem === 'function') {
            highlightTimelineItem(index);
        }
    }

    // ─── Loading State ────────────────────────────────────────────────────────

    showLoading(containerId) {
        const el = document.getElementById(containerId);
        if (!el) return;
        el.innerHTML = `
            <div class="text-center py-4 text-muted">
                <div class="spinner-border spinner-border-sm me-2" role="status"></div>
                Loading...
            </div>`;
    }

    hideLoading(containerId, html) {
        const el = document.getElementById(containerId);
        if (!el) return;
        if (html !== undefined) {
            el.innerHTML = html;
        }
    }

    // ─── Utilities ────────────────────────────────────────────────────────────

    formatTimestamp(timestamp) {
        if (!timestamp) return '—';
        const date = new Date(timestamp);
        if (isNaN(date.getTime())) return '—';
        const now = new Date();
        const diffMs = now - date;
        const diffSec = Math.floor(diffMs / 1000);
        const diffMin = Math.floor(diffSec / 60);
        const diffHr = Math.floor(diffMin / 60);
        const diffDay = Math.floor(diffHr / 24);

        if (diffSec < 60) return diffSec + 's ago';
        if (diffMin < 60) return diffMin + 'm ago';
        if (diffHr < 24) return diffHr + 'h ago';
        if (diffDay === 1) return 'Yesterday';
        return diffDay + 'd ago';
    }

    showAlert(message, type) {
        const alertDiv = document.createElement('div');
        alertDiv.className = `alert alert-${type || 'info'} alert-dismissible fade show position-fixed top-0 start-50 translate-middle-x mt-3`;
        alertDiv.style.zIndex = '9999';
        alertDiv.style.minWidth = '300px';
        alertDiv.innerHTML = `
            ${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        `;
        document.body.appendChild(alertDiv);
        setTimeout(() => { if (alertDiv.parentNode) alertDiv.remove(); }, 5000);
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    _clearRoutePolyline() {
        if (this.routePolyline && this.map) {
            this.map.removeLayer(this.routePolyline);
            this.routePolyline = null;
        }
    }

    _getInitials(name) {
        if (!name) return '?';
        const parts = name.trim().split(/\s+/);
        if (parts.length === 1) return parts[0].charAt(0).toUpperCase();
        return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
    }

    _employeeColor(id) {
        const colors = ['#2563eb', '#7c3aed', '#db2777', '#dc2626', '#d97706', '#059669', '#0891b2'];
        const num = parseInt(String(id).replace(/\D/g, '').slice(-4) || '0', 10);
        return colors[Math.abs(num) % colors.length];
    }

    _createEmployeeIcon(initials, color) {
        return L.divIcon({
            className: '',
            html: `<div style="background:${color};color:#fff;border-radius:50%;width:36px;height:36px;display:flex;align-items:center;justify-content:center;font-size:13px;font-weight:700;box-shadow:0 2px 8px rgba(0,0,0,0.3);border:3px solid #fff">${initials}</div>`,
            iconSize: [36, 36],
            iconAnchor: [18, 18],
            popupAnchor: [0, -20]
        });
    }

    _buildPopupContent(loc) {
        const name = loc.employee_name || loc.name || 'Unknown';
        const dept = loc.department || '';
        const desg = loc.designation || '';
        const time = this.formatTimestamp(loc.timestamp || loc.last_seen);
        const lat = parseFloat(loc.latitude || 0).toFixed(6);
        const lng = parseFloat(loc.longitude || 0).toFixed(6);
        return `
            <div style="min-width:160px">
                <strong>${name}</strong><br>
                ${dept ? `<small class="text-muted">${dept}${desg ? ' &middot; ' + desg : ''}</small><br>` : ''}
                <small><i class="fas fa-clock"></i> ${time}</small><br>
                <small class="text-muted">${lat}, ${lng}</small>
            </div>
        `;
    }

    _getCSRFToken() {
        const cookies = document.cookie.split(';');
        for (let c of cookies) {
            const parts = c.trim().split('=');
            if (parts[0] === 'csrftoken') return decodeURIComponent(parts[1] || '');
        }
        const meta = document.querySelector('meta[name=csrf-token]');
        return meta ? meta.getAttribute('content') : '';
    }
}
