package ironlib

import (
	"github.com/metal-toolbox/ironlib/errs"
	"github.com/metal-toolbox/ironlib/model"
	"github.com/metal-toolbox/ironlib/providers/asrockrack"
	"github.com/metal-toolbox/ironlib/providers/dell"
	"github.com/metal-toolbox/ironlib/providers/generic"
	"github.com/metal-toolbox/ironlib/providers/supermicro"
	"github.com/metal-toolbox/ironlib/utils"
	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
)

// New returns a device Manager interface based on the hardware deviceVendor, model attributes
// by default returns a Generic device instance that only returns the device inventory
func New(logger *logrus.Logger) (m model.DeviceManager, err error) {
	dmidecode, err := utils.NewDmidecode()
	if err != nil {
		return nil, errors.Wrap(errs.ErrDmiDecodeRun, err.Error())
	}

	deviceVendor, err := dmidecode.Manufacturer()
	if err != nil {
		return nil, errors.Wrap(errs.NewDmidecodeValueError("system manufacturer", "", 0), err.Error())
	}

	if deviceVendor == "" || deviceVendor == model.SystemManufacturerUndefined {
		deviceVendor, err = dmidecode.BaseBoardManufacturer()
		if err != nil {
			return nil, errors.Wrap(errs.NewDmidecodeValueError("baseboard manufacturer", "", 0), err.Error())
		}
	}

	deviceVendor = model.FormatVendorName(deviceVendor)

	switch deviceVendor {
	case model.VendorDell:
		return dell.New(dmidecode, logger)
	case model.VendorSupermicro:
		return supermicro.New(dmidecode, logger)
	case model.VendorPacket, model.VendorAsrockrack:
		return asrockrack.New(dmidecode, logger)
	default:
		return generic.New(dmidecode, logger)
	}
}

// Logformat adds default fields to each log entry.
type LogFormat struct {
	Fields    logrus.Fields
	Formatter logrus.Formatter
}

// Format satisfies the logrus.Formatter interface.
func (f *LogFormat) Format(e *logrus.Entry) ([]byte, error) {
	for k, v := range f.Fields {
		e.Data[k] = v
	}

	return f.Formatter.Format(e)
}
