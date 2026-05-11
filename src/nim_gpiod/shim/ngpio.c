#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "ngpio.h"

#include <linux/gpio.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef GPIO_V2_GET_LINE_IOCTL
#error "GPIO character device ABI v2 is required: GPIO_V2_GET_LINE_IOCTL is missing"
#endif

#define NGPIO_MAX_CHIPS 256
#define NGPIO_PATH_MAX 64
#define NGPIO_ERROR_MAX 256

struct ngpio {
    int chip_fd;
    int event_fd;
    unsigned int offset;
    int active_low;
    char chip_path[NGPIO_PATH_MAX];
    char consumer[GPIO_MAX_NAME_SIZE];
    char last_error[NGPIO_ERROR_MAX];
};

static char ngpio_global_error[NGPIO_ERROR_MAX];

static void set_error_buf(char *buf, size_t size, const char *fmt, ...)
{
    va_list ap;

    if (buf == NULL || size == 0) {
        return;
    }

    va_start(ap, fmt);
    vsnprintf(buf, size, fmt, ap);
    va_end(ap);
}

static void set_global_error(const char *fmt, ...)
{
    va_list ap;

    va_start(ap, fmt);
    vsnprintf(ngpio_global_error, sizeof(ngpio_global_error), fmt, ap);
    va_end(ap);
}

static void set_error(ngpio_t *gpio, const char *fmt, ...)
{
    va_list ap;

    if (gpio == NULL) {
        return;
    }

    va_start(ap, fmt);
    vsnprintf(gpio->last_error, sizeof(gpio->last_error), fmt, ap);
    va_end(ap);
}

static void copy_cstr(char *dst, size_t dst_size, const char *src)
{
    if (dst == NULL || dst_size == 0) {
        return;
    }

    if (src == NULL) {
        dst[0] = '\0';
        return;
    }

    snprintf(dst, dst_size, "%s", src);
}

static int open_chip(const char *chip_path)
{
    return open(chip_path, O_RDONLY | O_CLOEXEC);
}

static int request_input_fd(ngpio_t *gpio)
{
    struct gpio_v2_line_request req;
    uint64_t flags;
    int rc;

    if (gpio == NULL) {
        errno = EINVAL;
        return -1;
    }

    memset(&req, 0, sizeof(req));

    flags = GPIO_V2_LINE_FLAG_INPUT;
    if (gpio->active_low) {
        flags |= GPIO_V2_LINE_FLAG_ACTIVE_LOW;
    }

    req.offsets[0] = gpio->offset;
    req.num_lines = 1;
    req.config.flags = flags;
    copy_cstr(req.consumer, sizeof(req.consumer), gpio->consumer);

    rc = ioctl(gpio->chip_fd, GPIO_V2_GET_LINE_IOCTL, &req);
    if (rc < 0) {
        set_error(gpio,
                  "GPIO_V2_GET_LINE_IOCTL(input) failed for %s offset %u: %s",
                  gpio->chip_path,
                  gpio->offset,
                  strerror(errno));
        return -1;
    }

    return req.fd;
}

static int find_line_by_name(const char *line_name,
                             char *out_chip_path,
                             size_t out_chip_path_size,
                             unsigned int *out_offset)
{
    char chip_path[NGPIO_PATH_MAX];
    int chip_fd;
    int found;
    unsigned int chip_index;

    if (line_name == NULL || line_name[0] == '\0') {
        set_global_error("line name is empty");
        return -1;
    }

    found = 0;

    for (chip_index = 0; chip_index < NGPIO_MAX_CHIPS; chip_index++) {
        struct gpiochip_info chip_info;
        unsigned int offset;

        snprintf(chip_path, sizeof(chip_path), "/dev/gpiochip%u", chip_index);

        chip_fd = open_chip(chip_path);
        if (chip_fd < 0) {
            continue;
        }

        memset(&chip_info, 0, sizeof(chip_info));
        if (ioctl(chip_fd, GPIO_GET_CHIPINFO_IOCTL, &chip_info) < 0) {
            close(chip_fd);
            continue;
        }

        for (offset = 0; offset < chip_info.lines; offset++) {
            struct gpio_v2_line_info line_info;

            memset(&line_info, 0, sizeof(line_info));
            line_info.offset = offset;

            if (ioctl(chip_fd, GPIO_V2_GET_LINEINFO_IOCTL, &line_info) < 0) {
                continue;
            }

            if (strncmp(line_info.name, line_name, GPIO_MAX_NAME_SIZE) == 0) {
                copy_cstr(out_chip_path, out_chip_path_size, chip_path);
                *out_offset = offset;
                found = 1;
                break;
            }
        }

        close(chip_fd);

        if (found) {
            return 0;
        }
    }

    set_global_error("GPIO line '%s' was not found", line_name);
    return -1;
}

ngpio_t *ngpio_open_by_chip_offset(const char *chip_path,
                                   unsigned int offset,
                                   const char *consumer,
                                   int active_low)
{
    ngpio_t *gpio;
    struct gpiochip_info chip_info;

    if (chip_path == NULL || chip_path[0] == '\0') {
        set_global_error("chip path is empty");
        return NULL;
    }

    gpio = calloc(1, sizeof(*gpio));
    if (gpio == NULL) {
        set_global_error("calloc failed: %s", strerror(errno));
        return NULL;
    }

    gpio->chip_fd = open_chip(chip_path);
    if (gpio->chip_fd < 0) {
        set_global_error("failed to open %s: %s", chip_path, strerror(errno));
        free(gpio);
        return NULL;
    }

    memset(&chip_info, 0, sizeof(chip_info));
    if (ioctl(gpio->chip_fd, GPIO_GET_CHIPINFO_IOCTL, &chip_info) < 0) {
        set_global_error("GPIO_GET_CHIPINFO_IOCTL failed for %s: %s",
                         chip_path,
                         strerror(errno));
        close(gpio->chip_fd);
        free(gpio);
        return NULL;
    }

    if (offset >= chip_info.lines) {
        set_global_error("offset %u is out of range for %s: lines=%u",
                         offset,
                         chip_path,
                         chip_info.lines);
        close(gpio->chip_fd);
        free(gpio);
        return NULL;
    }

    gpio->event_fd = -1;
    gpio->offset = offset;
    gpio->active_low = active_low ? 1 : 0;

    copy_cstr(gpio->chip_path, sizeof(gpio->chip_path), chip_path);

    if (consumer == NULL || consumer[0] == '\0') {
        copy_cstr(gpio->consumer, sizeof(gpio->consumer), "nim_gpiod");
    } else {
        copy_cstr(gpio->consumer, sizeof(gpio->consumer), consumer);
    }

    gpio->last_error[0] = '\0';
    return gpio;
}

ngpio_t *ngpio_open_by_line_name(const char *line_name,
                                 const char *consumer,
                                 int active_low)
{
    char chip_path[NGPIO_PATH_MAX];
    unsigned int offset;

    if (find_line_by_name(line_name, chip_path, sizeof(chip_path), &offset) < 0) {
        return NULL;
    }

    return ngpio_open_by_chip_offset(chip_path, offset, consumer, active_low);
}

int ngpio_get_value(ngpio_t *gpio, int *value)
{
    struct gpio_v2_line_values values;
    int req_fd;
    int rc;

    if (gpio == NULL || value == NULL) {
        errno = EINVAL;
        return -1;
    }

    req_fd = request_input_fd(gpio);
    if (req_fd < 0) {
        return -1;
    }

    memset(&values, 0, sizeof(values));
    values.mask = 1;

    rc = ioctl(req_fd, GPIO_V2_LINE_GET_VALUES_IOCTL, &values);
    if (rc < 0) {
        set_error(gpio,
                  "GPIO_V2_LINE_GET_VALUES_IOCTL failed for %s offset %u: %s",
                  gpio->chip_path,
                  gpio->offset,
                  strerror(errno));
        close(req_fd);
        return -1;
    }

    *value = (values.bits & 1) ? 1 : 0;

    close(req_fd);
    return 0;
}

int ngpio_request_edge_events(ngpio_t *gpio, ngpio_edge_t edge)
{
    struct gpio_v2_line_request req;
    uint64_t flags;
    int rc;

    if (gpio == NULL) {
        errno = EINVAL;
        return -1;
    }

    if (gpio->event_fd >= 0) {
        return 0;
    }

    memset(&req, 0, sizeof(req));

    flags = GPIO_V2_LINE_FLAG_INPUT;

    if (gpio->active_low) {
        flags |= GPIO_V2_LINE_FLAG_ACTIVE_LOW;
    }

    switch (edge) {
    case NGPIO_EDGE_RISING:
        flags |= GPIO_V2_LINE_FLAG_EDGE_RISING;
        break;
    case NGPIO_EDGE_FALLING:
        flags |= GPIO_V2_LINE_FLAG_EDGE_FALLING;
        break;
    case NGPIO_EDGE_BOTH:
        flags |= GPIO_V2_LINE_FLAG_EDGE_RISING | GPIO_V2_LINE_FLAG_EDGE_FALLING;
        break;
    default:
        set_error(gpio, "invalid edge value: %d", (int)edge);
        errno = EINVAL;
        return -1;
    }

    req.offsets[0] = gpio->offset;
    req.num_lines = 1;
    req.config.flags = flags;
    req.event_buffer_size = 16;
    copy_cstr(req.consumer, sizeof(req.consumer), gpio->consumer);

    rc = ioctl(gpio->chip_fd, GPIO_V2_GET_LINE_IOCTL, &req);
    if (rc < 0) {
        set_error(gpio,
                  "GPIO_V2_GET_LINE_IOCTL(edge) failed for %s offset %u: %s",
                  gpio->chip_path,
                  gpio->offset,
                  strerror(errno));
        return -1;
    }

    gpio->event_fd = req.fd;
    return 0;
}

int ngpio_get_event_fd(ngpio_t *gpio)
{
    if (gpio == NULL) {
        errno = EINVAL;
        return -1;
    }

    if (gpio->event_fd < 0) {
        set_error(gpio, "edge events are not requested");
        errno = EBADF;
        return -1;
    }

    return gpio->event_fd;
}

int ngpio_read_event(ngpio_t *gpio, ngpio_event_t *event)
{
    struct gpio_v2_line_event raw_event;
    ssize_t nread;

    if (gpio == NULL || event == NULL) {
        errno = EINVAL;
        return -1;
    }

    if (gpio->event_fd < 0) {
        set_error(gpio, "edge events are not requested");
        errno = EBADF;
        return -1;
    }

    memset(&raw_event, 0, sizeof(raw_event));

    nread = read(gpio->event_fd, &raw_event, sizeof(raw_event));
    if (nread < 0) {
        set_error(gpio,
                  "read(edge event) failed for %s offset %u: %s",
                  gpio->chip_path,
                  gpio->offset,
                  strerror(errno));
        return -1;
    }

    if ((size_t)nread != sizeof(raw_event)) {
        set_error(gpio,
                  "short read(edge event) for %s offset %u: got %zd expected %zu",
                  gpio->chip_path,
                  gpio->offset,
                  nread,
                  sizeof(raw_event));
        errno = EIO;
        return -1;
    }

    memset(event, 0, sizeof(*event));

    switch (raw_event.id) {
    case GPIO_V2_LINE_EVENT_RISING_EDGE:
        event->edge = NGPIO_EVENT_RISING;
        break;
    case GPIO_V2_LINE_EVENT_FALLING_EDGE:
        event->edge = NGPIO_EVENT_FALLING;
        break;
    default:
        set_error(gpio, "unknown GPIO event id: %u", raw_event.id);
        errno = EPROTO;
        return -1;
    }

    event->timestamp_ns = raw_event.timestamp_ns;
    event->seqno = raw_event.seqno;
    event->line_seqno = raw_event.line_seqno;

    return 0;
}

int ngpio_release_events(ngpio_t *gpio)
{
    if (gpio == NULL) {
        errno = EINVAL;
        return -1;
    }

    if (gpio->event_fd >= 0) {
        close(gpio->event_fd);
        gpio->event_fd = -1;
    }

    return 0;
}

const char *ngpio_last_error(const ngpio_t *gpio)
{
    if (gpio == NULL) {
        return ngpio_global_error;
    }

    return gpio->last_error;
}

const char *ngpio_last_error_global(void)
{
    return ngpio_global_error;
}

void ngpio_close(ngpio_t *gpio)
{
    if (gpio == NULL) {
        return;
    }

    ngpio_release_events(gpio);

    if (gpio->chip_fd >= 0) {
        close(gpio->chip_fd);
        gpio->chip_fd = -1;
    }

    free(gpio);
}
