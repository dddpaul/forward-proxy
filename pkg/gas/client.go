package gas

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/http/httptrace"
	"net/url"
	"strings"

	"github.com/dddpaul/http-over-socks-proxy/pkg/logger"
	"github.com/dddpaul/http-over-socks-proxy/pkg/transport"
)

const DF = "2006-01-02 15:04:05 -0700"

type GASConfig struct {
	Url          string
	Socks        string
	ClientID     string
	ClientSecret string
}

type Client struct {
	url    *url.URL
	trace  *httptrace.ClientTrace
	client *http.Client
}

type Status int64

const (
	OK    Status = 0
	ERROR        = 1
)

type Response struct {
	Status  Status `json:"status"`
	Message string `json:"message"`
}

func (r *Response) isError() bool {
	return r.Status != OK
}

func NewClient(ctx context.Context, gas *GASConfig, command string) *Client {
	u, err := url.Parse(gas.Url)
	if err != nil {
		panic(err)
	}
	params := url.Values{}
	params.Add("client_id", gas.ClientID)
	params.Add("client_secret", gas.ClientSecret)
	params.Add("command", command)
	u.RawQuery = params.Encode()

	return &Client{
		url:   u,
		trace: transport.NewTrace(ctx),
		client: &http.Client{
			Transport:     transport.NewSocksTransport(gas.Socks),
			CheckRedirect: transport.LogRedirect,
		},
	}
}

func (c *Client) Get(ctx context.Context) (string, error) {
	logger.Log(ctx, nil).WithField("url", c.url.String()).Debugf("request")

	req, err := http.NewRequestWithContext(
		httptrace.WithClientTrace(ctx, c.trace),
		"GET",
		c.url.String(),
		nil)
	if err != nil {
		return "", err
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return "", err
	}

	r, err := parse(resp)
	if err != nil {
		return "", err
	}
	logger.Log(ctx, nil).WithField("body", fmt.Sprintf("%+v", r)).Debugf("response")

	return r.Message, nil
}

// Parse HTTP response from Google App Script
func parse(resp *http.Response) (*Response, error) {
	data, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	resp.Body.Close()

	s := string(data)
	if strings.Contains(s, ".errorMessage") {
		return nil, errors.New("GAS: " + after(s, "Error: "))
	}

	r := &Response{}
	if err = json.Unmarshal(data, r); err != nil {
		return nil, err
	}

	if r.isError() {
		return nil, errors.New("GAS: " + r.Message)
	}

	return r, nil
}

// Get substring after a string
func after(s string, a string) string {
	pos := strings.LastIndex(s, a)
	if pos == -1 {
		return ""
	}
	adjustedPos := pos + len(a)
	if adjustedPos >= len(s) {
		return ""
	}
	return s[adjustedPos : len(s)-1]
}
