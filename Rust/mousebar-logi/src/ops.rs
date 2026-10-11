//! The operations behind the exported functions, written against OpenLogi's
//! public API and returning the JSON shapes MouseBar decodes.

use std::sync::Arc;

use hidpp::device::Device;
use hidpp::feature::CreatableFeature;
use hidpp::feature::report_rate::{ReportRateFeature, ReportRateList};
use openlogi_core::device::{BatteryInfo, BatteryStatus, DeviceKind};
use openlogi_hid::{DeviceRoute, Dpi, WriteError};
use serde::Serialize;

/// One paired device, as `mb_logi_enumerate` lists it.
#[derive(Serialize)]
pub(crate) struct DeviceEntry {
    /// The serde JSON of the [`DeviceRoute`] that reaches the device, handed
    /// back unchanged to the per-device functions.
    route: String,
    receiver_name: String,
    receiver_product_id: u16,
    slot: u8,
    wpid: Option<u16>,
    codename: Option<String>,
    kind: DeviceKind,
    online: bool,
    battery: Option<Battery>,
}

#[derive(Serialize)]
pub(crate) struct Battery {
    percent: u8,
    charging: bool,
}

impl From<&BatteryInfo> for Battery {
    fn from(info: &BatteryInfo) -> Self {
        Self {
            percent: info.percentage,
            charging: matches!(
                info.status,
                BatteryStatus::Charging | BatteryStatus::ChargingSlow
            ),
        }
    }
}

/// Readable settings; a part is `None` when the device lacks its feature.
#[derive(Serialize)]
pub(crate) struct Settings {
    dpi: Option<DpiSettings>,
    report_rate: Option<ReportRateSettings>,
}

#[derive(Serialize)]
pub(crate) struct DpiSettings {
    current: u16,
    supported: Vec<u16>,
}

#[derive(Serialize)]
pub(crate) struct ReportRateSettings {
    current_ms: u8,
    supported_ms: Vec<u8>,
}

/// Every paired device of every receiver (or direct attachment) on this host.
///
/// A device whose route cannot be built (its receiver reported no unique id)
/// is left out: nothing could address it afterwards.
pub(crate) async fn enumerate() -> Result<Vec<DeviceEntry>, String> {
    let inventories = openlogi_hid::enumerate()
        .await
        .map_err(|error| error.to_string())?;
    let mut devices = Vec::new();
    for inventory in &inventories {
        for paired in &inventory.paired {
            let Some(route) = DeviceRoute::for_slot(inventory, paired.slot) else {
                continue;
            };
            devices.push(DeviceEntry {
                route: serde_json::to_string(&route).map_err(|error| error.to_string())?,
                receiver_name: inventory.receiver.name.clone(),
                receiver_product_id: inventory.receiver.product_id,
                slot: paired.slot,
                wpid: paired.wpid,
                codename: paired.codename.clone(),
                kind: paired.kind,
                online: paired.online,
                battery: paired.battery.as_ref().map(Battery::from),
            });
        }
    }
    Ok(devices)
}

/// DPI and report rate of the device `route` reaches.
pub(crate) async fn read_settings(route: &DeviceRoute) -> Result<Settings, String> {
    let dpi = match openlogi_hid::get_dpi_info(route).await {
        Ok(info) => Some(DpiSettings {
            current: u16::from(info.current),
            supported: info
                .capabilities
                .values()
                .iter()
                .map(|&dpi| u16::from(dpi))
                .collect(),
        }),
        Err(WriteError::FeatureUnsupported { .. }) => None,
        Err(error) => return Err(error.to_string()),
    };
    let report_rate = match open_report_rate(route).await? {
        Some(feature) => Some(ReportRateSettings {
            supported_ms: supported_intervals(&feature).await?,
            current_ms: feature
                .get_report_rate()
                .await
                .map_err(|error| error.to_string())?,
        }),
        None => None,
    };
    Ok(Settings { dpi, report_rate })
}

/// Battery of the device `route` reaches, `None` when it is offline or absent.
///
/// OpenLogi's per-route battery read (`read_battery` with its feature-specific
/// percentage mapping) is private to its inventory module, so this takes the
/// battery a fresh enumeration reports for the matching device.
pub(crate) async fn read_battery(route: &DeviceRoute) -> Result<Option<Battery>, String> {
    let inventories = openlogi_hid::enumerate()
        .await
        .map_err(|error| error.to_string())?;
    let device = inventories.iter().find_map(|inventory| {
        inventory
            .paired
            .iter()
            .find(|paired| DeviceRoute::for_slot(inventory, paired.slot).as_ref() == Some(route))
    });
    Ok(device
        .filter(|paired| paired.online)
        .and_then(|paired| paired.battery.as_ref())
        .map(Battery::from))
}

/// Write the sensor DPI of the device `route` reaches.
pub(crate) async fn set_dpi(route: &DeviceRoute, dpi: u32) -> Result<(), String> {
    let dpi = Dpi::try_from(dpi).map_err(|_| "unsupported dpi".to_owned())?;
    openlogi_hid::set_dpi(route, dpi)
        .await
        .map_err(|error| error.to_string())
}

/// Write the report interval of the device `route` reaches, when it is one the
/// device lists as supported.
pub(crate) async fn set_report_rate(route: &DeviceRoute, interval_ms: u8) -> Result<(), String> {
    const UNSUPPORTED: &str = "unsupported report rate";
    let feature = open_report_rate(route)
        .await?
        .ok_or_else(|| UNSUPPORTED.to_owned())?;
    if !supported_intervals(&feature).await?.contains(&interval_ms) {
        return Err(UNSUPPORTED.to_owned());
    }
    feature
        .set_report_rate(interval_ms)
        .await
        .map_err(|error| error.to_string())
}

/// The `0x8060 ReportRate` feature of the device `route` reaches, or `None`
/// when the device does not expose it.
///
/// Reached the way OpenLogi's DPI writes reach theirs: open the channel the
/// route names, address the device at the route's index, look the feature up
/// in its root table.
async fn open_report_rate(route: &DeviceRoute) -> Result<Option<Arc<ReportRateFeature>>, String> {
    let channel = openlogi_hid::channel_pool()
        .open(route)
        .await
        .map_err(|error| error.to_string())?
        .ok_or_else(|| WriteError::DeviceNotFound.to_string())?;
    let index = route.device_index();
    let mut device = Device::new(channel, index)
        .await
        .map_err(|_| WriteError::DeviceUnreachable { index }.to_string())?;
    let feature = device
        .root()
        .get_feature(ReportRateFeature::ID)
        .await
        .map_err(|error| error.to_string())?;
    Ok(feature.map(|info| device.add_feature::<ReportRateFeature>(info.index)))
}

/// The report intervals the device accepts, in milliseconds, ascending.
async fn supported_intervals(feature: &ReportRateFeature) -> Result<Vec<u8>, String> {
    let list = feature
        .get_report_rate_list()
        .await
        .map_err(|error| error.to_string())?;
    Ok(intervals(list))
}

/// Bit `n` of the `0x8060` list means an interval of `n + 1` ms.
fn intervals(list: ReportRateList) -> Vec<u8> {
    (1..=8u8)
        .filter(|ms| list.bits() & (1 << (ms - 1)) != 0)
        .collect()
}
