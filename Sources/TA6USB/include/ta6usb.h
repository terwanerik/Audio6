#pragma once
#include <stdint.h>

typedef struct {
    uint16_t vid;
    uint16_t pid;
    char name[128];
} ta6_device_info;

// List all USB devices (up to max). Returns the number written.
int  ta6_list(ta6_device_info *out, int max);

// Choose which device to talk to. pid 0 = any product from that vendor
// (then a device named "...Audio 6..." is preferred). Default: 0x17CC / 0.
void ta6_set_target(uint16_t vid, uint16_t pid);

// All functions below return 0 on success. The device is opened lazily and
// re-opened automatically after it has been unplugged.
int  ta6_open(void);
void ta6_close(void);
int  ta6_read(uint8_t request, uint16_t index, uint8_t *value);
int  ta6_write(uint8_t request, uint16_t value, uint16_t index);

// Last error: -2 = no matching device, -3 = plug-in failed (see kr),
// -4 = QueryInterface failed, other = IOReturn from the request.
int  ta6_last_error(void);
