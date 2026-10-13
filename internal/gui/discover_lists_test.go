package gui

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDiscoverListMutationValidation(t *testing.T) {
	s := newTestServer(t)
	for _, body := range []string{`{`, `{}`, `{"action":"../user"}`, `{"action":"create","title":" "}`, `{"action":"remove-folder"}`, `{"action":"add","item":"1"}`, `{"action":"remove-item","folder":"2"}`} {
		w := httptest.NewRecorder()
		s.handleDiscoverBookmarkMutation(w, httptest.NewRequest(http.MethodPost, "/api/discover/bookmarks", strings.NewReader(body)))
		if w.Code != http.StatusBadRequest {
			t.Errorf("body %s: status %d, want 400", body, w.Code)
		}
	}
	for _, body := range []string{`{}`, `{"id":" "}`, `{`} {
		w := httptest.NewRecorder()
		s.handleDiscoverSubscription(w, httptest.NewRequest(http.MethodPost, "/api/discover/subscription", strings.NewReader(body)))
		if w.Code != http.StatusBadRequest {
			t.Errorf("subscription body %s: status %d, want 400", body, w.Code)
		}
	}
}

func TestDiscoverListMutationsRequireAuthentication(t *testing.T) {
	s := newTestServer(t)
	cases := []struct {
		path, body string
		handler    http.HandlerFunc
	}{
		{"/api/discover/bookmarks", `{"action":"create","title":"Films"}`, s.handleDiscoverBookmarkMutation},
		{"/api/discover/subscription", `{"id":"1"}`, s.handleDiscoverSubscription},
		{"/api/discover/bookmark-folders?id=1", "", s.handleDiscoverBookmarkFolders},
	}
	for _, c := range cases {
		w := httptest.NewRecorder()
		c.handler(w, httptest.NewRequest(http.MethodPost, c.path, strings.NewReader(c.body)))
		if w.Code != http.StatusUnauthorized {
			t.Errorf("%s: status %d, want 401", c.path, w.Code)
		}
	}
}
