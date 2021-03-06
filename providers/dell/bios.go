package dell

import (
	"context"
	"os"

	"github.com/metal-toolbox/ironlib/model"
	"github.com/metal-toolbox/ironlib/utils"
)

func (d *dell) SetBIOSConfiguration(ctx context.Context, cfg map[string]string) error {
	return nil
}

func (d *dell) GetBIOSConfiguration(ctx context.Context) (map[string]string, error) {
	if envRacadmUtil := os.Getenv("UTIL_RACADM7"); envRacadmUtil == "" {
		err := d.pre() // ensure runtime pre-requisites are installed
		if err != nil {
			return nil, err
		}
	}

	racadm := utils.NewDellRacadm(false)

	return racadm.GetBIOSConfiguration(ctx, model.FormatProductName(d.GetModel()))
}
