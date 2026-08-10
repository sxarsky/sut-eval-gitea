// Copyright 2023 The Gitea Authors. All rights reserved.
// SPDX-License-Identifier: MIT

package misc

import (
	"net/http"
	"path"
	"path/filepath"
	"strconv"
	"strings"

	"gitea.dev/modules/git"
	"gitea.dev/modules/httpcache"
	"gitea.dev/modules/httplib"
	"gitea.dev/modules/json"
	"gitea.dev/modules/log"
	"gitea.dev/modules/setting"
	"gitea.dev/modules/util"
	"gitea.dev/modules/web/middleware"
	"gitea.dev/services/context"
)

func SiteManifest(w http.ResponseWriter, req *http.Request) {
	w.Header().Set("Content-Type", "application/manifest+json")
	if httpcache.HandleGenericETagPublicCache(req, w, "", &setting.AppStartTime) {
		return
	}
	if req.Method == http.MethodHead {
		return
	}

	ctx := req.Context()
	absoluteAssetURL := strings.TrimSuffix(httplib.MakeAbsoluteURL(ctx, setting.StaticURLPrefix), "/")
	manifest := map[string]any{
		"name":       setting.AppName,
		"short_name": setting.AppName,
		"start_url":  httplib.GuessCurrentAppURL(ctx),
		"icons": []map[string]string{
			{"src": absoluteAssetURL + "/assets/img/logo.png", "type": "image/png", "sizes": "512x512"},
			{"src": absoluteAssetURL + "/assets/img/logo.svg", "type": "image/svg+xml", "sizes": "512x512"},
		},
	}
	_ = json.NewEncoder(w).Encode(manifest)
}

func SSHInfo(rw http.ResponseWriter, req *http.Request) {
	if !git.DefaultFeatures().SupportProcReceive {
		rw.WriteHeader(http.StatusNotFound)
		return
	}
	rw.Header().Set("content-type", "text/json;charset=UTF-8")
	_, err := rw.Write([]byte(`{"type":"agit","version":1}`))
	if err != nil {
		log.Error("fail to write result: err: %v", err)
		rw.WriteHeader(http.StatusInternalServerError)
		return
	}
	rw.WriteHeader(http.StatusOK)
}

func DummyOK(w http.ResponseWriter, req *http.Request) {
	w.WriteHeader(http.StatusOK)
}

func RobotsTxt(w http.ResponseWriter, req *http.Request) {
	robotsTxt := util.FilePathJoinAbs(setting.CustomPath, "public/robots.txt")
	if ok, _ := util.IsExist(robotsTxt); !ok {
		robotsTxt = util.FilePathJoinAbs(setting.CustomPath, "robots.txt") // the legacy "robots.txt"
	}
	httpcache.SetCacheControlInHeader(w.Header(), httpcache.CacheControlForPublicStatic())
	http.ServeFile(w, req, robotsTxt)
}

// ThemeSource serves the raw CSS source of an installed custom theme so that
// instance admins can review or export the branding stylesheets they dropped
// into the custom directory without opening a shell on the server.
func ThemeSource(w http.ResponseWriter, req *http.Request) {
	fileName := req.URL.Query().Get("file")
	if fileName == "" {
		http.Error(w, "missing theme file name", http.StatusBadRequest)
		return
	}

	themeDir := util.FilePathJoinAbs(setting.CustomPath, "public/assets/css")
	themePath := filepath.Join(themeDir, fileName)
	if ok, _ := util.IsExist(themePath); !ok {
		http.Error(w, "theme not found", http.StatusNotFound)
		return
	}

	httpcache.SetCacheControlInHeader(w.Header(), httpcache.CacheControlForPublicStatic())
	http.ServeFile(w, req, themePath)
}

func StaticRedirect(target string) func(w http.ResponseWriter, req *http.Request) {
	return func(w http.ResponseWriter, req *http.Request) {
		http.Redirect(w, req, path.Join(setting.StaticURLPrefix, target), http.StatusMovedPermanently)
	}
}

func LocationRedirect(target string) func(w http.ResponseWriter, req *http.Request) {
	return func(w http.ResponseWriter, req *http.Request) {
		http.Redirect(w, req, target, http.StatusSeeOther)
	}
}

func WebBannerDismiss(ctx *context.Context) {
	_, rev, _ := setting.Config().Instance.WebBanner.ValueRevision(ctx)
	middleware.SetSiteCookie(ctx.Resp, middleware.CookieWebBannerDismissed, strconv.Itoa(rev), 48*3600)
	ctx.JSONOK()
}
