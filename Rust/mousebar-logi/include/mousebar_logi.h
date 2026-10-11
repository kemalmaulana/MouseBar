#ifndef MOUSEBAR_LOGI_H
#define MOUSEBAR_LOGI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Every char * result is UTF-8 JSON {"ok": <value>} or {"error": "<message>"}. */

/* {"ok":{"crate":"0.1.0","openlogi_rev":"<sha>"}}; free with mb_logi_free. */
char *mb_logi_version(void);

/* {"ok":[Device, ...]} for every paired device; free with mb_logi_free. */
char *mb_logi_enumerate(void);

/* {"ok":Settings} (dpi, report_rate; each null when unsupported) for route; free with mb_logi_free. */
char *mb_logi_read_settings(const char *route);

/* {"ok":{"percent":80,"charging":false}} or {"ok":null} when unreachable; free with mb_logi_free. */
char *mb_logi_read_battery(const char *route);

/* Writes sensor DPI, {"ok":null} on success; free with mb_logi_free. */
char *mb_logi_set_dpi(const char *route, uint32_t dpi);

/* Writes report interval in ms if supported, {"ok":null} on success; free with mb_logi_free. */
char *mb_logi_set_report_rate(const char *route, uint8_t interval_ms);

/* Releases a string returned by this library; NULL is a no-op. */
void mb_logi_free(char *s);

#ifdef __cplusplus
}
#endif

#endif /* MOUSEBAR_LOGI_H */
