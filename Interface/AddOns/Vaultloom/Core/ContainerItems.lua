local _, Addon = ...

local ContainerItems = {}
Addon.ContainerItems = ContainerItems

function ContainerItems:GetButtonIcon(button)
    if not button then
        return nil
    end

    local icon = button.icon or button.Icon or button.IconTexture or button.iconTexture
    if icon then
        return icon
    end

    local name = button.GetName and button:GetName() or nil
    if type(name) == "string" and name ~= "" then
        return _G[name .. "IconTexture"] or _G[name .. "Icon"] or _G[name .. "icon"]
    end

    return nil
end

function ContainerItems:GetButtonBagAndSlot(button)
    if not button or (button.IsForbidden and button:IsForbidden()) then
        return nil, nil
    end

    local name = button.GetName and button:GetName() or nil
    local slotID
    local bagID

    if type(button.GetSlotAndBagID) == "function" then
        local ok, resolvedSlotID, resolvedBagID = pcall(button.GetSlotAndBagID, button)
        if ok then
            slotID = tonumber(resolvedSlotID)
            bagID = tonumber(resolvedBagID)
        end
    end

    if slotID == nil then
        if type(button.GetID) == "function" then
            local ok, resolvedSlotID = pcall(button.GetID, button)
            if ok then
                slotID = tonumber(resolvedSlotID)
            end
        end
        slotID = slotID or tonumber(button.slot)
    end

    if bagID == nil and type(button.GetBagID) == "function" then
        local ok, resolvedBagID = pcall(button.GetBagID, button)
        if ok then
            bagID = tonumber(resolvedBagID)
        end
    end
    bagID = bagID or tonumber(button.bagID or button.BagID)

    if bagID == nil and button.GetParent then
        local parent = button:GetParent()
        local guard = 0
        while parent and guard < 4 and bagID == nil do
            if type(parent.GetBagID) == "function" then
                local ok, resolvedBagID = pcall(parent.GetBagID, parent)
                if ok then
                    bagID = tonumber(resolvedBagID)
                end
            end

            if bagID == nil and guard == 0 and type(parent.GetID) == "function" then
                local ok, resolvedBagID = pcall(parent.GetID, parent)
                if ok then
                    bagID = tonumber(resolvedBagID)
                end
            end

            parent = parent.GetParent and parent:GetParent() or nil
            guard = guard + 1
        end
    end

    if type(name) == "string" and slotID == nil then
        slotID = tonumber(name:match("^ReagentBankFrameItem(%d+)$"))
            or tonumber(name:match("^BankPanelItem(%d+)$"))
            or tonumber(name:match("^BankFrameItem(%d+)$"))
    end

    if bagID == nil and type(name) == "string" then
        if name:match("^ReagentBankFrameItem%d+$") then
            bagID = tonumber(REAGENTBANK_CONTAINER)
        elseif name:match("^BankPanelItem%d+$") or name:match("^BankFrameItem%d+$") then
            bagID = tonumber(BANK_CONTAINER)
        end
    end

    if bagID == nil or slotID == nil or slotID < 1 then
        return nil, nil
    end

    return bagID, slotID
end

function ContainerItems:GetItemLink(bagID, slotID)
    if C_Container and type(C_Container.GetContainerItemLink) == "function" then
        local ok, itemLink = pcall(C_Container.GetContainerItemLink, bagID, slotID)
        if ok then
            return itemLink
        end
    end

    if type(GetContainerItemLink) == "function" then
        local ok, itemLink = pcall(GetContainerItemLink, bagID, slotID)
        if ok then
            return itemLink
        end
    end

    return nil
end

function ContainerItems:GetQuality(bagID, slotID, itemLink)
    local quality

    if bagID ~= nil and slotID ~= nil and C_Container and type(C_Container.GetContainerItemInfo) == "function" then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bagID, slotID)
        if ok and type(info) == "table" then
            quality = tonumber(info.quality or info.qualityID)
        end
    elseif bagID ~= nil and slotID ~= nil and type(GetContainerItemInfo) == "function" then
        local ok, _, _, _, resolvedQuality = pcall(GetContainerItemInfo, bagID, slotID)
        if ok then
            quality = tonumber(resolvedQuality)
        end
    end

    if quality == nil and itemLink and type(GetItemInfo) == "function" then
        local ok, _, _, resolvedQuality = pcall(GetItemInfo, itemLink)
        if ok then
            quality = tonumber(resolvedQuality)
        end
    end

    return quality
end

function ContainerItems:GetButtonItemLink(button, bagID, slotID)
    if bagID ~= nil and slotID ~= nil then
        local itemLink = self:GetItemLink(bagID, slotID)
        if type(itemLink) == "string" and itemLink ~= "" then
            return itemLink
        end
    end

    if button and type(button.GetItemLocation) == "function"
        and C_Item and type(C_Item.GetItemLink) == "function"
    then
        local okLocation, itemLocation = pcall(button.GetItemLocation, button)
        if okLocation and itemLocation then
            local okLink, itemLink = pcall(C_Item.GetItemLink, itemLocation)
            if okLink and type(itemLink) == "string" and itemLink ~= "" then
                return itemLink
            end
        end
    end

    local itemLocation = button and (button.itemLocation or button.ItemLocation) or nil
    if itemLocation and C_Item and type(C_Item.GetItemLink) == "function" then
        local ok, itemLink = pcall(C_Item.GetItemLink, itemLocation)
        if ok and type(itemLink) == "string" and itemLink ~= "" then
            return itemLink
        end
    end

    if button and type(button.GetItem) == "function" then
        local ok, _, itemLink = pcall(button.GetItem, button)
        if ok and type(itemLink) == "string" and itemLink ~= "" then
            return itemLink
        end
    end

    local itemLink = button and (button.itemLink or button.link or button.hyperlink) or nil
    if type(itemLink) == "string" and itemLink ~= "" then
        return itemLink
    end

    return nil
end
