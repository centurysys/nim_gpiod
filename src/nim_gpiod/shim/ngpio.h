#ifndef NGPIO_H
#define NGPIO_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

typedef struct ngpio ngpio_t;

typedef enum ngpio_edge {
    NGPIO_EDGE_RISING = 1,
    NGPIO_EDGE_FALLING = 2,
    NGPIO_EDGE_BOTH = 3,
} ngpio_edge_t;

typedef enum ngpio_event_edge {
    NGPIO_EVENT_RISING = 1,
    NGPIO_EVENT_FALLING = 2,
} ngpio_event_edge_t;

typedef struct ngpio_event {
    ngpio_event_edge_t edge;
    uint64_t timestamp_ns;
    uint32_t seqno;
    uint32_t line_seqno;
} ngpio_event_t;

ngpio_t *ngpio_open_by_line_name(const char *line_name,
                                 const char *consumer,
                                 int active_low);

ngpio_t *ngpio_open_by_chip_offset(const char *chip_path,
                                   unsigned int offset,
                                   const char *consumer,
                                   int active_low);

int ngpio_get_value(ngpio_t *gpio, int *value);

int ngpio_request_edge_events(ngpio_t *gpio, ngpio_edge_t edge);
int ngpio_get_event_fd(ngpio_t *gpio);
int ngpio_read_event(ngpio_t *gpio, ngpio_event_t *event);
int ngpio_release_events(ngpio_t *gpio);

const char *ngpio_last_error(const ngpio_t *gpio);
const char *ngpio_last_error_global(void);

void ngpio_close(ngpio_t *gpio);

#ifdef __cplusplus
}
#endif

#endif
