# Quick Test Guide - JavaScript Map Tracking

## Prerequisites

1. **Leaflet.js**: Automatically loaded from CDN (no API key required)
   - OpenStreetMap tiles are used (free, no API key needed)

2. **Static Files**: Ensure static files are collected (for production) or served (for development)
   ```bash
   python manage.py collectstatic  # For production
   ```

3. **Database**: Ensure migrations are applied
   ```bash
   python manage.py migrate
   ```

4. **Sample Data**: Create at least one employee and some location logs for testing

## Testing Live Tracking

### Steps:
1. **Start Django server:**
   ```bash
   python manage.py runserver
   ```

2. **Login to dashboard:**
   - Navigate to `/dashboard/`
   - Login with admin credentials

3. **Open Live Tracking:**
   - Click "Live Tracking" in sidebar
   - URL: `/dashboard/live-tracking/`

4. **Verify:**
   - [ ] Map loads (OpenStreetMap tiles visible)
   - [ ] Markers appear for active employees (if any)
   - [ ] Auto-refresh works (check console for API calls every 30s)
   - [ ] Employee list sidebar shows employees
   - [ ] Click marker shows info window
   - [ ] Search box filters employee list
   - [ ] Refresh button works manually

### Expected Behavior:
- Map centers on employee locations
- Markers are colored (green=online, orange=late, red=absent)
- Info windows show: name, ID, timestamp, address, battery, speed
- Employee list updates every 30 seconds
- Countdown timer shows time until next refresh

## Testing Route History

### Steps:
1. **Open Route History:**
   - Click "Route History" in sidebar
   - URL: `/dashboard/route-history/`

2. **Load a Route:**
   - Select an employee from dropdown
   - Select a date (must have location logs)
   - Optionally set start/end time
   - Click "Load Route"

3. **Verify:**
   - [ ] Map loads
   - [ ] Route polyline draws on map
   - [ ] Start marker (green "S") appears
   - [ ] End marker (red "E") appears
   - [ ] Timeline shows all locations
   - [ ] Play button starts playback
   - [ ] Pause button pauses playback
   - [ ] Speed controls work (0.5x, 1x, 2x, 5x)
   - [ ] Progress bar updates during playback
   - [ ] Clicking timeline item jumps to location
   - [ ] Reset button clears playback

### Expected Behavior:
- Route polyline is blue, 4px wide
- Playback marker (orange) animates along route
- Map centers on current playback location
- Timeline item highlights during playback
- Progress shows "current/total" locations

## Common Issues & Solutions

### Issue: Map doesn't load
**Solution:**
- Check browser console for errors
- Verify Leaflet.js is loaded from CDN
- Check internet connection (Leaflet loads from CDN)
- Ensure Leaflet CSS is loaded

### Issue: No markers appear
**Solution:**
- Check if employees have location logs
- Verify API endpoint returns data: `/api/tracking/live-locations/`
- Check browser console for API errors
- Verify user is authenticated

### Issue: Route doesn't load
**Solution:**
- Verify employee has location logs for selected date
- Check API endpoint: `/api/tracking/employee-route/`
- Check browser console for errors
- Verify date format is correct (YYYY-MM-DD)

### Issue: Playback doesn't work
**Solution:**
- Ensure route data loaded successfully
- Check browser console for JavaScript errors
- Verify MapTracking class is loaded
- Check if Leaflet.js is loaded

### Issue: CSRF token errors
**Solution:**
- Verify CSRF middleware is enabled
- Check if user is logged in
- Verify cookies are enabled
- Check CSRF token in request headers

## Browser Console Checks

Open browser DevTools (F12) and check:

1. **Network Tab:**
   - API calls return 200 status
   - Response contains expected data
   - No CORS errors

2. **Console Tab:**
   - No JavaScript errors
   - MapTracking class is defined
   - Leaflet.js (L) is loaded and available

3. **Application Tab:**
   - Cookies include `csrftoken`
   - Session cookie exists

## API Endpoints to Test

### Live Locations
```bash
GET /api/tracking/live-locations/
Headers: X-CSRFToken: <token>
```

### Employee Route
```bash
GET /api/tracking/employee-route/?employee_id=<uuid>&date=2024-01-15
Headers: X-CSRFToken: <token>
```

### Employees List
```bash
GET /api/employees/
Headers: X-CSRFToken: <token>
```

## Performance Checks

1. **Map Loading:**
   - Should load within 2-3 seconds
   - No lag when panning/zooming

2. **Auto-refresh:**
   - Updates every 30 seconds
   - No performance degradation over time

3. **Route Playback:**
   - Smooth animation
   - No stuttering at different speeds
   - Memory usage stays reasonable

## Mobile Testing

Test on mobile devices:
- [ ] Map loads correctly
- [ ] Touch gestures work (pan, zoom)
- [ ] Markers are clickable
- [ ] Info windows display properly
- [ ] Sidebar is accessible
- [ ] Playback controls work

## Next Steps After Testing

If everything works:
1. ✅ Implementation is complete
2. ✅ Ready for production use
3. ✅ Can add more features as needed

If issues found:
1. Check error messages in console
2. Verify API responses
3. Check network connectivity
4. Review JavaScript code for errors

## Support

For issues:
1. Check browser console for errors
2. Verify API endpoints return data
3. Check Django logs: `logs/django.log`
4. Verify environment variables are set
5. Check static files are served correctly
