#include "ta6usb.h"

#include <string.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

static IOUSBDeviceInterface **g_dev = NULL;
static uint16_t g_vid = 0x17CC, g_pid = 0;
static int g_err = 0;

int ta6_last_error(void) { return g_err; }

void ta6_set_target(uint16_t vid, uint16_t pid) {
    ta6_close();
    g_vid = vid;
    g_pid = pid;
}

static int get_u16(io_service_t s, CFStringRef key, uint16_t *out) {
    CFTypeRef v = IORegistryEntryCreateCFProperty(s, key, kCFAllocatorDefault, 0);
    int ok = 0;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) {
        int x = 0;
        CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &x);
        *out = (uint16_t)x;
        ok = 1;
    }
    if (v) CFRelease(v);
    return ok;
}

static void get_name(io_service_t s, char *buf, size_t n) {
    buf[0] = 0;
    CFTypeRef v = IORegistryEntryCreateCFProperty(s, CFSTR("USB Product Name"), kCFAllocatorDefault, 0);
    if (!v) v = IORegistryEntryCreateCFProperty(s, CFSTR("kUSBProductString"), kCFAllocatorDefault, 0);
    if (v && CFGetTypeID(v) == CFStringGetTypeID())
        CFStringGetCString((CFStringRef)v, buf, (CFIndex)n, kCFStringEncodingUTF8);
    if (v) CFRelease(v);
    if (!buf[0]) {
        io_name_t nm;
        if (IORegistryEntryGetName(s, nm) == KERN_SUCCESS) strlcpy(buf, nm, n);
    }
}

// Iterate over all USB devices (new and legacy class names)
static io_iterator_t usb_devices(void) {
    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(MACH_PORT_NULL, IOServiceMatching("IOUSBHostDevice"), &it) == KERN_SUCCESS
        && IOIteratorIsValid(it)) {
        return it;
    }
    IOServiceGetMatchingServices(MACH_PORT_NULL, IOServiceMatching("IOUSBDevice"), &it);
    return it;
}

int ta6_list(ta6_device_info *out, int max) {
    io_iterator_t it = usb_devices();
    if (!it) return 0;
    int n = 0;
    io_service_t s;
    while ((s = IOIteratorNext(it))) {
        if (n < max) {
            memset(&out[n], 0, sizeof out[n]);
            get_u16(s, CFSTR("idVendor"), &out[n].vid);
            get_u16(s, CFSTR("idProduct"), &out[n].pid);
            get_name(s, out[n].name, sizeof out[n].name);
            n++;
        }
        IOObjectRelease(s);
    }
    IOObjectRelease(it);
    return n;
}

int ta6_open(void) {
    if (g_dev) return 0;

    io_iterator_t it = usb_devices();
    if (!it) { g_err = -2; return g_err; }

    io_service_t s, chosen = 0;
    while ((s = IOIteratorNext(it))) {
        uint16_t vid = 0, pid = 0;
        get_u16(s, CFSTR("idVendor"), &vid);
        get_u16(s, CFSTR("idProduct"), &pid);
        if (vid != g_vid || (g_pid && pid != g_pid)) { IOObjectRelease(s); continue; }

        char name[128];
        get_name(s, name, sizeof name);
        if (g_pid || strstr(name, "Audio 6")) {       // exact or preferred match
            if (chosen) IOObjectRelease(chosen);
            chosen = s;
            break;
        }
        if (!chosen) chosen = s; else IOObjectRelease(s);
    }
    IOObjectRelease(it);
    if (!chosen) { g_err = -2; return g_err; }

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score;
    kern_return_t kr = IOCreatePlugInInterfaceForService(
        chosen, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(chosen);
    if (kr != KERN_SUCCESS || !plugin) { g_err = kr ? (int)kr : -3; return -3; }

    HRESULT hr = (*plugin)->QueryInterface(
        plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&g_dev);
    IODestroyPlugInInterface(plugin);
    if (hr != S_OK || !g_dev) { g_dev = NULL; g_err = -4; return g_err; }

    g_err = 0;
    return 0;
}

void ta6_close(void) {
    if (g_dev) {
        (*g_dev)->Release(g_dev);
        g_dev = NULL;
    }
}

static int control(uint8_t type, uint8_t req, uint16_t value, uint16_t index,
                   void *data, uint16_t len) {
    if (ta6_open() != 0) return -1;
    IOUSBDevRequest r = {0};
    r.bmRequestType = type;
    r.bRequest = req;
    r.wValue = value;
    r.wIndex = index;
    r.wLength = len;
    r.pData = data;
    IOReturn kr = (*g_dev)->DeviceRequest(g_dev, &r);
    if (kr != kIOReturnSuccess) {
        g_err = (int)kr;
        ta6_close();   // probably unplugged; reopen on next call
        return -1;
    }
    g_err = 0;
    return 0;
}

int ta6_read(uint8_t request, uint16_t index, uint8_t *value) {
    return control(0xC0, request, 0, index, value, 1);   // vendor, device-to-host
}

int ta6_write(uint8_t request, uint16_t value, uint16_t index) {
    return control(0x40, request, value, index, NULL, 0); // vendor, host-to-device
}
