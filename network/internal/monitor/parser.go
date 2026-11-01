package monitor

import (
	"encoding/json"
	"github.com/MrMohebi/token-current/network/internal/protocol"
	"time"
)

type Context struct {
	Session      string
	Started      float64
	Forked       bool
	BaselineSeen bool
}
type Observation struct {
	Key      string
	Counts   protocol.Counts
	Time     time.Time
	Baseline bool
	Initial  *protocol.Counts
}
type usage struct {
	Input  *int64 `json:"input_tokens"`
	Output *int64 `json:"output_tokens"`
	Cached int64  `json:"cached_input_tokens"`
	Write  int64  `json:"cache_write_input_tokens"`
	Read   int64  `json:"cache_read_input_tokens"`
	Create int64  `json:"cache_creation_input_tokens"`
}
type row struct {
	Type      string `json:"type"`
	Timestamp string `json:"timestamp"`
	Request   string `json:"requestId"`
	Message   *struct {
		ID    string `json:"id"`
		Usage *usage `json:"usage"`
	} `json:"message"`
	Payload *struct {
		ID        string `json:"id"`
		Type      string `json:"type"`
		Timestamp string `json:"timestamp"`
		Forked    string `json:"forked_from_id"`
		Thread    string `json:"thread_id"`
		Usage     *usage `json:"usage"`
		Total     *usage `json:"thread_token_usage"`
		Info      *struct {
			Total *usage `json:"total_token_usage"`
			Last  *usage `json:"last_token_usage"`
		} `json:"info"`
	} `json:"payload"`
}

func Parse(data []byte, provider, file string, context *Context) (*Observation, bool) {
	var r row
	if json.Unmarshal(data, &r) != nil {
		return nil, true
	}
	if provider == "codex" && r.Type == "session_meta" && r.Payload != nil {
		context.Session = r.Payload.ID
		context.Forked = r.Payload.Forked != ""
		stamp := r.Payload.Timestamp
		if stamp == "" {
			stamp = r.Timestamp
		}
		if t, e := time.Parse(time.RFC3339Nano, stamp); e == nil {
			context.Started = float64(t.UnixNano()) / 1e9
		}
		return nil, false
	}
	var u, last *usage
	key := ""
	baseline := false
	var initial *protocol.Counts
	if provider == "claude" {
		if r.Type != "assistant" || r.Message == nil || r.Message.Usage == nil {
			return nil, false
		}
		u = r.Message.Usage
		key = "claude:" + r.Message.ID + ":" + r.Request
		if r.Message.ID == "" {
			return nil, true
		}
	} else {
		if r.Payload == nil || (r.Payload.Type != "token_count" && r.Type != "token_usage_record") {
			return nil, false
		}
		if r.Payload.Info != nil {
			u = r.Payload.Info.Total
			last = r.Payload.Info.Last
		} else {
			u = r.Payload.Total
			last = r.Payload.Usage
		}
		if u == nil {
			return nil, r.Type == "token_usage_record"
		}
		session := context.Session
		if session == "" {
			session = file
		}
		if r.Payload.Thread != "" {
			session = r.Payload.Thread
		}
		key = "codex:" + session
	}
	t, err := time.Parse(time.RFC3339Nano, r.Timestamp)
	if err != nil || u.Input == nil || u.Output == nil || *u.Input < 0 || *u.Output < 0 || *u.Input > 1e15 || *u.Output > 1e15 {
		return nil, true
	}
	c := protocol.Counts{Input: *u.Input, Output: *u.Output, CacheRead: u.Cached, CacheWrite: u.Write}
	if provider == "claude" {
		if u.Read < 0 || u.Create < 0 || u.Read > 1e15 || u.Create > 1e15 {
			return nil, true
		}
		c.Input += u.Read + u.Create
		c.CacheRead = u.Read
		c.CacheWrite = u.Create
	}
	if !c.Valid() {
		return nil, true
	}
	if provider == "codex" && context.Forked {
		inherited := float64(t.UnixNano())/1e9 < context.Started
		if inherited && r.Payload.Thread != "" && r.Payload.Thread != context.Session {
			return nil, false
		}
		if !context.BaselineSeen && !inherited && last != nil && last.Input != nil && last.Output != nil && *last.Input >= 0 && *last.Output >= 0 && *last.Input <= c.Input && *last.Output <= c.Output {
			b := protocol.Counts{Input: c.Input - *last.Input, Output: c.Output - *last.Output, CacheRead: max(0, c.CacheRead-last.Cached), CacheWrite: max(0, c.CacheWrite-last.Write)}
			initial = &b
		}
		baseline = inherited || (!context.BaselineSeen && initial == nil)
		context.BaselineSeen = true
	}
	return &Observation{key, c, t, baseline, initial}, false
}
