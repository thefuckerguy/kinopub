package kinopubapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestBookmarkMutationsUseMobileAPIContract(t *testing.T) {
	for _, action := range []string{"create", "remove-folder", "add", "remove-item"} {
		t.Run(action, func(t *testing.T) {
			srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodPost || r.URL.Path != "/v1/bookmarks/"+action {
					t.Errorf("unexpected request: %s %s", r.Method, r.URL.Path)
				}
				q := r.URL.Query()
				if q.Get("item") != "42" || q.Get("folder") != "7" || q.Get("title") != "Кино & more" || q.Get("access_token") != "tok" {
					t.Error("missing or incorrect mutation parameters")
				}
				_, _ = w.Write([]byte(`{"status":200}`))
			}))
			defer srv.Close()
			if err := newTestClient(srv).MutateBookmark(context.Background(), action, "42", "7", "Кино & more"); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestSubscriptionRequiresExplicitReturnedState(t *testing.T) {
	for _, body := range []string{`{"watching":1}`, `{"watching":false}`, `{"watching":"1"}`, `{}`} {
		h := &recordingHandler{body: body}
		srv := httptest.NewServer(h)
		state, err := newTestClient(srv).ToggleSubscription(context.Background(), "42")
		srv.Close()
		if body == `{}` {
			if err == nil {
				t.Error("missing state must fail")
			}
			continue
		}
		if err != nil {
			t.Fatal(err)
		}
		if state != (body != `{"watching":false}`) {
			t.Errorf("body %s: state %v", body, state)
		}
		if h.lastReq.Method != http.MethodGet || h.lastReq.URL.Path != "/v1/watching/togglewatchlist" || h.lastURL.Get("id") != "42" {
			t.Error("wrong subscription contract")
		}
	}
}

func TestFlexibleBool(t *testing.T) {
	for _, s := range []string{"true", "1", `"1"`, `"true"`, "false", "0", `"0"`, "null"} {
		var b FlexibleBool
		if err := json.Unmarshal([]byte(s), &b); err != nil {
			t.Fatalf("%s: %v", s, err)
		}
	}
	var b FlexibleBool
	if json.Unmarshal([]byte(`"unknown"`), &b) == nil {
		t.Error("invalid state accepted")
	}
}

func TestBookmarkFoldersMembershipResponse(t *testing.T) {
	h := &recordingHandler{body: `{"folders":[{"id":7,"title":"Favorites"}]}`}
	srv := httptest.NewServer(h)
	defer srv.Close()
	folders, err := newTestClient(srv).BookmarkFolders(context.Background(), "42")
	if err != nil {
		t.Fatal(err)
	}
	if len(folders) != 1 || folders[0].ID.String() != "7" || h.lastURL.Get("item") != "42" {
		t.Fatal("membership contract mismatch")
	}
}
