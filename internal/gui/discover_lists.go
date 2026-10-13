package gui

import (
	"net/http"
	"strings"
)

func (s *Server) handleDiscoverBookmarkFolders(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if id == "" {
		writeErr(w, http.StatusBadRequest, "id is required")
		return
	}
	client, ok := s.kpClientOrErr(w)
	if !ok {
		return
	}
	folders, err := client.BookmarkFolders(r.Context(), id)
	if err != nil {
		s.kpFail(w, err)
		return
	}
	out := make([]DiscoverBookmark, 0, len(folders))
	for _, f := range folders {
		out = append(out, DiscoverBookmark{ID: f.ID.String(), Title: f.Title, Count: f.Count})
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out})
}

func (s *Server) handleDiscoverBookmarkMutation(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Action string `json:"action"`
		Item   string `json:"item"`
		Folder string `json:"folder"`
		Title  string `json:"title"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	body.Title = strings.TrimSpace(body.Title)
	valid := false
	switch body.Action {
	case "create":
		valid = body.Title != "" && len(body.Title) <= 200
	case "remove-folder":
		valid = strings.TrimSpace(body.Folder) != ""
	case "add", "remove-item":
		valid = strings.TrimSpace(body.Item) != "" && strings.TrimSpace(body.Folder) != ""
	}
	if !valid {
		writeErr(w, http.StatusBadRequest, "invalid bookmark action or missing fields")
		return
	}
	client, ok := s.kpClientOrErr(w)
	if !ok {
		return
	}
	if err := client.MutateBookmark(r.Context(), body.Action, body.Item, body.Folder, body.Title); err != nil {
		s.kpFail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleDiscoverSubscription(w http.ResponseWriter, r *http.Request) {
	var body struct {
		ID string `json:"id"`
	}
	if err := decodeJSON(w, r, &body); err != nil {
		writeErr(w, http.StatusBadRequest, err.Error())
		return
	}
	if strings.TrimSpace(body.ID) == "" {
		writeErr(w, http.StatusBadRequest, "id is required")
		return
	}
	client, ok := s.kpClientOrErr(w)
	if !ok {
		return
	}
	subscribed, err := client.ToggleSubscription(r.Context(), body.ID)
	if err != nil {
		s.kpFail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"subscribed": subscribed})
}
