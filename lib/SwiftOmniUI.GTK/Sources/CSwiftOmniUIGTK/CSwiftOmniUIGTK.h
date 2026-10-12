// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// GTK 4 and libadwaita, as Swift imports them.
#include <adwaita.h>

// Fontconfig and Pango's cairo font map, for the fonts an application carries:
// fontconfig's list of application fonts is where a file registers, and the
// default font map Pango reads its families from.
#include <fontconfig/fontconfig.h>
#include <pango/pangocairo.h>

// The fontconfig font map, declared incomplete - pangofc's own header pulls in
// freetype's, which needn't stand on this path for one call.
typedef struct _PangoFcFontMap PangoFcFontMap;
void pango_fc_font_map_config_changed(PangoFcFontMap *fontmap);

/// The font file at `path`, added to the current fontconfig's application
/// fonts: every family inside it answers `pango_attr_family_new`'s names from
/// then on, a font map made before being told the configuration changed.
/// Whether the platform took it.
static inline gboolean swiftomniui_gtk_font_added(const char *path) {
    if (!path || !*path) return FALSE;
    if (!FcConfigAppFontAddFile(FcConfigGetCurrent(), (const FcChar8 *)path)) return FALSE;
    pango_fc_font_map_config_changed((PangoFcFontMap *)pango_cairo_font_map_get_default());
    return TRUE;
}

// GLib marks its flags as flag enumerations from 2.86, which Swift then imports as option sets naming their members
// itself - G_SIGNAL_MATCH_DATA is no longer in scope. The flags Swift passes stand here under one name on every GLib.
static const GApplicationFlags SWIFTOMNIUI_APPLICATION_DEFAULT_FLAGS = G_APPLICATION_DEFAULT_FLAGS;
static const GApplicationFlags SWIFTOMNIUI_APPLICATION_NON_UNIQUE = G_APPLICATION_NON_UNIQUE;
static const GSignalMatchType SWIFTOMNIUI_SIGNAL_MATCH_ID = G_SIGNAL_MATCH_ID;
static const GSignalMatchType SWIFTOMNIUI_SIGNAL_MATCH_DATA = G_SIGNAL_MATCH_DATA;
static const GDBusProxyFlags SWIFTOMNIUI_DBUS_PROXY_FLAGS_NONE = G_DBUS_PROXY_FLAGS_NONE;
static const GDBusProxyFlags SWIFTOMNIUI_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START = G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START;
static const GFileTest SWIFTOMNIUI_FILE_TEST_IS_REGULAR = G_FILE_TEST_IS_REGULAR;
