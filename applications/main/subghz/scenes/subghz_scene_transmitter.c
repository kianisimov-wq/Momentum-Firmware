#include "../subghz_i.h"
#include "../views/transmitter.h"
#include <dolphin/dolphin.h>

#include <lib/subghz/blocks/custom_btn.h>
#include <lib/subghz/devices/devices.c>

#include "applications/main/subghz/helpers/subghz_txrx_i.h"

#define TAG "SubGhzSceneTransmitter"

static bool tx_stop_called = false;

void subghz_scene_transmitter_callback(SubGhzCustomEvent event, void* context) {
    furi_assert(context);
    SubGhz* subghz = context;
    view_dispatcher_send_custom_event(subghz->view_dispatcher, event);
}

bool subghz_scene_transmitter_update_data_show(void* context) {
    SubGhz* subghz = context;
    bool ret = false;
    SubGhzProtocolDecoderBase* decoder = subghz_txrx_get_decoder(subghz->txrx);

    if(decoder) {
        FuriString* key_str = furi_string_alloc();
        FuriString* frequency_str = furi_string_alloc();
        FuriString* modulation_str = furi_string_alloc();

        if(subghz_protocol_decoder_base_deserialize(
               decoder, subghz_txrx_get_fff_data(subghz->txrx)) == SubGhzProtocolStatusOk) {
            subghz_protocol_decoder_base_get_string(decoder, key_str);

            subghz_txrx_get_frequency_and_modulation(
                subghz->txrx, frequency_str, modulation_str, false);
            subghz_view_transmitter_add_data_to_show(
                subghz->subghz_transmitter,
                furi_string_get_cstr(key_str),
                furi_string_get_cstr(frequency_str),
                furi_string_get_cstr(modulation_str),
                subghz_txrx_protocol_is_transmittable(subghz->txrx, false));
            ret = true;
        }
        furi_string_free(frequency_str);
        furi_string_free(modulation_str);
        furi_string_free(key_str);
    }
    subghz_view_transmitter_set_radio_device_type(
        subghz->subghz_transmitter, subghz_txrx_radio_device_get(subghz->txrx));
    return ret;
}

void subghz_scene_transmitter_on_enter(void* context) {
    SubGhz* subghz = context;

    subghz_custom_btns_reset();

    if(!subghz_scene_transmitter_update_data_show(subghz)) {
        view_dispatcher_send_custom_event(
            subghz->view_dispatcher, SubGhzCustomEventViewTransmitterError);
    }

    subghz_view_transmitter_set_callback(
        subghz->subghz_transmitter, subghz_scene_transmitter_callback, subghz);

    subghz->state_notifications = SubGhzNotificationStateIDLE;
    view_dispatcher_switch_to_view(subghz->view_dispatcher, SubGhzViewIdTransmitter);
}

bool subghz_scene_transmitter_on_event(void* context, SceneManagerEvent event) {
    SubGhz* subghz = context;
    if(event.type == SceneManagerEventTypeCustom) {
        if(event.event == SubGhzCustomEventViewTransmitterSendStart) {
            // if we recieve event to start transmission (user press OK button) then start/restart TX
            subghz->state_notifications = SubGhzNotificationStateIDLE;

            if(subghz_tx_start(subghz, subghz_txrx_get_fff_data(subghz->txrx))) {
                subghz->state_notifications = SubGhzNotificationStateTx;
                subghz_scene_transmitter_update_data_show(subghz);
                dolphin_deed(DolphinDeedSubGhzSend);
            }
            return true;
        } else if(event.event == SubGhzCustomEventViewTransmitterSendStop) {
            // we recieve event to stop tranmission (user release OK button) but
            // hardware TX still working now then set flag to stop it after hardware TX will be realy ended
            if(!subghz_devices_is_async_complete_tx(subghz->txrx->radio_device)) {
                tx_stop_called = true;
                return true;
            }
            // if hardware TX not working now so just stop TX correctly
            subghz->state_notifications = SubGhzNotificationStateIDLE;
            subghz_txrx_stop(subghz->txrx);
            if(subghz_custom_btn_get() != SUBGHZ_CUSTOM_BTN_OK) {
                subghz_custom_btn_set(SUBGHZ_CUSTOM_BTN_OK);
                int32_t tmp_counter = furi_hal_subghz_get_rolling_counter_mult();
                furi_hal_subghz_set_rolling_counter_mult(0);
                // Calling restore!
                subghz_tx_start(subghz, subghz_txrx_get_fff_data(subghz->txrx));
                subghz_txrx_stop(subghz->txrx);
                // Calling restore 2nd time special for FAAC SLH!
                // TODO: Find better way to restore after custom button is used!!!
                subghz_tx_start(subghz, subghz_txrx_get_fff_data(subghz->txrx));
                subghz_txrx_stop(subghz->txrx);
                furi_hal_subghz_set_rolling_counter_mult(tmp_counter);
            }
            return true;
        } else if(event.event == SubGhzCustomEventViewTransmitterBack) {
            // if user press back button then force stop TX if they was active
            if(subghz->state_notifications == SubGhzNotificationStateTx) {
                subghz_txrx_stop(subghz->txrx);
            }
            subghz->state_notifications = SubGhzNotificationStateIDLE;
            scene_manager_search_and_switch_to_previous_scene(
                subghz->scene_manager, SubGhzSceneStart);
            return true;
        } else if(event.event == SubGhzCustomEventViewTransmitterError) {
            furi_string_set(subghz->error_str, "Protocol not\nfound!");
            scene_manager_next_scene(subghz->scene_manager, SubGhzSceneShowErrorSub);
        }
    } else if(event.type == SceneManagerEventTypeTick) {
        if(subghz->state_notifications == SubGhzNotificationStateTx) {
            // if hardware TX still working at this time so we just blink led and do nothing
            if(!subghz_devices_is_async_complete_tx(subghz->txrx->radio_device)) {
                notification_message(subghz->notifications, &sequence_blink_magenta_10);
                return true;
            }
            // if hardware TX not working now and tx_stop_called = true
            // (mean user release OK button early than hardware TX was ended) then we stop TX
            if(tx_stop_called) {
                tx_stop_called = false;
                subghz->state_notifications = SubGhzNotificationStateIDLE;
                subghz_txrx_stop(subghz->txrx);
                if(subghz_custom_btn_get() != SUBGHZ_CUSTOM_BTN_OK) {
                    subghz_custom_btn_set(SUBGHZ_CUSTOM_BTN_OK);
                    int32_t tmp_counter = furi_hal_subghz_get_rolling_counter_mult();
                    furi_hal_subghz_set_rolling_counter_mult(0);
                    // Calling restore!
                    subghz_tx_start(subghz, subghz_txrx_get_fff_data(subghz->txrx));
                    subghz_txrx_stop(subghz->txrx);
                    // Calling restore 2nd time special for FAAC SLH!
                    // TODO: Find better way to restore after custom button is used!!!
                    subghz_tx_start(subghz, subghz_txrx_get_fff_data(subghz->txrx));
                    subghz_txrx_stop(subghz->txrx);
                    furi_hal_subghz_set_rolling_counter_mult(tmp_counter);
                }
                return true;
            } else {
                // if state_notifications == SubGhzNotificationStateTx but hardware TX was ended
                // and user still dont release OK button then we repeat transmission
                subghz->state_notifications = SubGhzNotificationStateIDLE;
                if(subghz_tx_start(subghz, subghz_txrx_get_fff_data(subghz->txrx))) {
                    subghz->state_notifications = SubGhzNotificationStateTx;
                    subghz_scene_transmitter_update_data_show(subghz);
                    dolphin_deed(DolphinDeedSubGhzSend);
                }
                return true;
            }
        }
        return true;
    }
    return false;
}

void subghz_scene_transmitter_on_exit(void* context) {
    SubGhz* subghz = context;
    subghz->state_notifications = SubGhzNotificationStateIDLE;

    subghz_txrx_reset_dynamic_and_custom_btns(subghz->txrx);
}
