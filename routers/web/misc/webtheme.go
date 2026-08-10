// Copyright 2025 The Gitea Authors. All rights reserved.
// SPDX-License-Identifier: MIT

package misc

import (
	"net/http"
	"path/filepath"

	"gitea.dev/modules/httpcache"
	"gitea.dev/modules/optional"
	"gitea.dev/modules/setting"
	"gitea.dev/modules/templates"
	"gitea.dev/modules/util"
	"gitea.dev/modules/web/middleware"
	"gitea.dev/services/context"
	user_service "gitea.dev/services/user"
	"gitea.dev/services/webtheme"
)

func WebThemeList(ctx *context.Context) {
	// When a `file` query parameter is supplied, return the raw CSS source of an
	// installed custom theme (from custom/public/assets/css) so admins can
	// review or export the branding stylesheet, instead of the theme list.
	if fileName := ctx.FormString("file"); fileName != "" {
		themeDir := util.FilePathJoinAbs(setting.CustomPath, "public/assets/css")
		themePath := filepath.Join(themeDir, fileName)
		if ok, _ := util.IsExist(themePath); !ok {
			ctx.HTTPError(http.StatusNotFound)
			return
		}
		httpcache.SetCacheControlInHeader(ctx.Resp.Header(), httpcache.CacheControlForPublicStatic())
		http.ServeFile(ctx.Resp, ctx.Req, themePath)
		return
	}

	curWebTheme := ctx.TemplateContext.CurrentWebTheme()
	renderUtils := templates.NewRenderUtils(ctx)
	allThemes := webtheme.GetAvailableThemes()

	var results []map[string]any
	for _, theme := range allThemes {
		results = append(results, map[string]any{
			"name":  renderUtils.RenderThemeItem(theme, 14),
			"value": theme.InternalName,
			"class": "item js-aria-clickable" + util.Iif(theme.InternalName == curWebTheme.InternalName, " selected", ""),
		})
	}
	ctx.JSON(http.StatusOK, map[string]any{"results": results})
}

func WebThemeApply(ctx *context.Context) {
	themeName := ctx.FormString("theme")
	if ctx.Doer != nil {
		opts := &user_service.UpdateOptions{Theme: optional.Some(themeName)}
		_ = user_service.UpdateUser(ctx, ctx.Doer, opts)
	} else {
		middleware.SetSiteCookie(ctx.Resp, middleware.CookieTheme, themeName, 0)
	}
}
