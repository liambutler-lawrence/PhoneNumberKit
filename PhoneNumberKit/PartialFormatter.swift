//
//  PartialFormatter.swift
//  PhoneNumberKit
//
//  Created by Roy Marmelstein on 29/11/2015.
//  Copyright © 2015 Roy Marmelstein. All rights reserved.
//

import Foundation

/// Partial formatter
public class PartialFormatter {
    
    let metadata = Metadata.sharedInstance
    let parser = PhoneNumberParser()
    let regex = RegularExpressions.sharedInstance
    
    let defaultRegion: String
    let defaultMetadata: MetadataTerritory?

    var currentMetadata: MetadataTerritory?
    var prefixBeforeNationalNumber =  String()
    var shouldAddSpaceAfterNationalPrefix = false

    //MARK: Lifecycle
    
    convenience init() {
        let region = PhoneNumberKit().defaultRegionCode()
        self.init(region: region)
    }
    
    /**
     Inits a partial formatter with a custom region
     
     - parameter region: ISO 639 compliant region code.
     
     - returns: PartialFormatter object
     */
    public init(region: String) {
        defaultRegion = region
        defaultMetadata = metadata.fetchMetadataForCountry(defaultRegion)
        currentMetadata = defaultMetadata
    }
    
    /**
     Formats a partial string (for use in TextField)
     
     - parameter rawNumber: Unformatted phone number string
     
     - returns: Formatted phone number string.
     */
    public func formatPartial(rawNumber: String) -> String {
        // Check if number is valid for parsing, if not return raw
        if isValidRawNumber(rawNumber) == false {
            return rawNumber
        }
        // Reset variables
        resetVariables()
        let iddFreeNumber = extractIDD(rawNumber)
        let normalizedNumber = parser.normalizePhoneNumber(iddFreeNumber)
        var nationalNumber = extractCountryCallingCode(normalizedNumber)
        nationalNumber = extractNationalPrefix(nationalNumber)
//        if nationalNumber.hasPrefix("0") {
//            nationalNumber = nationalNumber.substringFromIndex(nationalNumber.startIndex.advancedBy(1))
//            prefixBeforeNationalNumber.appendContentsOf("0")
//        }

        if let formats = availableFormats(nationalNumber) {
            if let formattedNumber = applyFormat(nationalNumber, formats: formats) {
                nationalNumber = formattedNumber
            }
            else if let firstFormat = formats.first, let template = createFormattingTemplate(firstFormat, rawNumber: nationalNumber) {
                nationalNumber = applyFormattingTemplate(template, rawNumber: nationalNumber)
            }
        }
        var finalNumber = String()
        if prefixBeforeNationalNumber.characters.count > 0 {
            finalNumber.appendContentsOf(prefixBeforeNationalNumber)
        }
        if shouldAddSpaceAfterNationalPrefix && prefixBeforeNationalNumber.characters.count > 0 && prefixBeforeNationalNumber.characters.last != separatorBeforeNationalNumber.characters.first  {
            finalNumber.appendContentsOf(separatorBeforeNationalNumber)
        }
        if nationalNumber.characters.count > 0 {
            finalNumber.appendContentsOf(nationalNumber)
        }
        if finalNumber.characters.last == separatorBeforeNationalNumber.characters.first {
            finalNumber = finalNumber.substringToIndex(finalNumber.endIndex.predecessor())
        }

        return finalNumber
    }
    
    //MARK: Formatting Functions
    
    internal func resetVariables() {
        currentMetadata = defaultMetadata
        prefixBeforeNationalNumber = String()
        shouldAddSpaceAfterNationalPrefix = false
    }
    
    //MARK: Formatting Tests
    
    internal func isValidRawNumber(rawNumber: String) -> Bool {
        if rawNumber.isEmpty || rawNumber.characters.count < 3 {
            return false
        }
        do {
            let validNumberMatches = try regex.regexMatches(validPhoneNumberPattern, string: rawNumber)
            let validStart = regex.stringPositionByRegex(validStartPattern, string: rawNumber)
            if validNumberMatches.count == 0 || validStart != 0 {
                return false
            }
        }
        catch {
            return false
        }
        return true
    }
    
    internal func isNanpaNumberWithNationalPrefix(rawNumber: String) -> Bool {
        if currentMetadata?.countryCode != 1 {
            return false
        }
        return (rawNumber.characters.first == "1" && String(rawNumber.characters.startIndex.advancedBy(1)) != "0" && String(rawNumber.characters.startIndex.advancedBy(1)) != "1")
    }
    
    func isFormatEligible(format: MetadataPhoneNumberFormat) -> Bool {
        guard let phoneFormat = format.format else {
            return false
        }
        do {
            let validRegex = try regex.regexWithPattern(eligibleAsYouTypePattern)
            if validRegex.firstMatchInString(phoneFormat, options: [], range: NSMakeRange(0, phoneFormat.characters.count)) != nil {
                return true
            }
        }
        catch {}
        return false
    }
    
    //MARK: Formatting Extractions
    
    func extractIDD(rawNumber: String) -> String {
        var processedNumber = rawNumber
        do {
            if let internationalPrefix = currentMetadata?.internationalPrefix {
                let prefixPattern = String(format: iddPattern, arguments: [internationalPrefix])
                let matches = try regex.matchedStringByRegex(prefixPattern, string: rawNumber)
                if let m = matches.first {
                    let startCallingCode = m.characters.count
                    let index = rawNumber.startIndex.advancedBy(startCallingCode)
                    processedNumber = rawNumber.substringFromIndex(index)
                    prefixBeforeNationalNumber = rawNumber.substringToIndex(index)
                }
            }
        }
        catch {
            return processedNumber
        }
        return processedNumber
    }
    
    func extractNationalPrefix(rawNumber: String) -> String {
        var processedNumber = rawNumber
        var startOfNationalNumber: Int = 0
        if isNanpaNumberWithNationalPrefix(rawNumber) {
            prefixBeforeNationalNumber.appendContentsOf("1 ")
        }
        else {
            do {
                if let nationalPrefix = currentMetadata?.nationalPrefixForParsing {
                    let nationalPrefixPattern = String(format: nationalPrefixParsingPattern, arguments: [nationalPrefix])
                    let matches = try regex.matchedStringByRegex(nationalPrefixPattern, string: rawNumber)
                    if let m = matches.first {
                        startOfNationalNumber = m.characters.count
                    }
                }
            }
            catch {
                return processedNumber
                }
        }
        let index = rawNumber.startIndex.advancedBy(startOfNationalNumber)
        processedNumber = rawNumber.substringFromIndex(index)
        prefixBeforeNationalNumber.appendContentsOf(rawNumber.substringToIndex(index))
        return processedNumber
    }
    
    func extractCountryCallingCode(rawNumber: String) -> String {
        var processedNumber = rawNumber
        if rawNumber.isEmpty {
            return rawNumber
        }
        var numberWithoutCountryCallingCode = String()
        if prefixBeforeNationalNumber.isEmpty == false && prefixBeforeNationalNumber.characters.first != "+" {
            prefixBeforeNationalNumber.appendContentsOf(separatorBeforeNationalNumber)
        }
        if let potentialCountryCode = self.parser.extractPotentialCountryCode(rawNumber, nationalNumber: &numberWithoutCountryCallingCode) where potentialCountryCode != 0 {
            processedNumber = numberWithoutCountryCallingCode
            currentMetadata = metadata.fetchMainCountryMetadataForCode(potentialCountryCode)
            prefixBeforeNationalNumber.appendContentsOf("\(potentialCountryCode) ")
        }
        return processedNumber
    }

    func availableFormats(rawNumber: String) -> [MetadataPhoneNumberFormat]? {
        var tempPossibleFormats = [MetadataPhoneNumberFormat]()
        var possibleFormats = [MetadataPhoneNumberFormat]()
        if let metadata = currentMetadata {
            let formatList = metadata.numberFormats
            for format in formatList {
                if isFormatEligible(format) {
                    tempPossibleFormats.append(format)
                }
                if let leadingDigitPattern = format.leadingDigitsPatterns?.last {
                    if (regex.stringPositionByRegex(leadingDigitPattern, string: String(rawNumber)) == 0) {
                        if (regex.matchesEntirely(format.pattern, string: String(rawNumber))) {
                            possibleFormats.append(format)
                        }
                    }
                }
                else {
                    if (regex.matchesEntirely(format.pattern, string: String(rawNumber))) {
                        possibleFormats.append(format)
                    }
                }
            }
            if possibleFormats.count == 0 {
                possibleFormats.appendContentsOf(tempPossibleFormats)
            }
            return possibleFormats
        }
        return nil
    }
    
    
    func applyFormat(rawNumber: String, formats: [MetadataPhoneNumberFormat]) -> String? {
        for format in formats {
            if let pattern = format.pattern, let formatTemplate = format.format {
                let patternRegExp = String(format: formatPattern, arguments: [pattern])
                do {
                    let matches = try regex.regexMatches(patternRegExp, string: rawNumber)
                    if matches.count > 0 {
                        if let nationalPrefixFormattingRule = format.nationalPrefixFormattingRule {
                            let separatorRegex = try regex.regexWithPattern(prefixSeparatorPattern)
                            let nationalPrefixMatches = separatorRegex.matchesInString(nationalPrefixFormattingRule, options: [], range:  NSMakeRange(0, nationalPrefixFormattingRule.characters.count))
                            if nationalPrefixMatches.count > 0 {
                                shouldAddSpaceAfterNationalPrefix = true
                            }
                        }
                        let formattedNumber = regex.replaceStringByRegex(pattern, string: rawNumber, template: formatTemplate)
                        return formattedNumber
                    }
                }
                catch {
                
                }
            }
        }
        return nil
    }
    
    
    
    func createFormattingTemplate(format: MetadataPhoneNumberFormat, rawNumber: String) -> String?  {
        guard var numberPattern = format.pattern, let numberFormat = format.format else {
            return nil
        }
        guard numberPattern.rangeOfString("|") == nil else {
            return nil
        }
        do {
            let characterClassRegex = try regex.regexWithPattern(characterClassPattern)
            var nsString = numberPattern as NSString
            var stringRange = NSMakeRange(0, nsString.length)
            numberPattern = characterClassRegex.stringByReplacingMatchesInString(numberPattern, options: [], range: stringRange, withTemplate: "\\\\d")
    
            let standaloneDigitRegex = try regex.regexWithPattern(standaloneDigitPattern)
            nsString = numberPattern as NSString
            stringRange = NSMakeRange(0, nsString.length)
            numberPattern = standaloneDigitRegex.stringByReplacingMatchesInString(numberPattern, options: [], range: stringRange, withTemplate: "\\\\d")
            
            if let tempTemplate = getFormattingTemplate(numberPattern, numberFormat: numberFormat, rawNumber: rawNumber) {
                if let nationalPrefixFormattingRule = format.nationalPrefixFormattingRule {
                    let separatorRegex = try regex.regexWithPattern(prefixSeparatorPattern)
                    let nationalPrefixMatch = separatorRegex.firstMatchInString(nationalPrefixFormattingRule, options: [], range:  NSMakeRange(0, nationalPrefixFormattingRule.characters.count))
                    if nationalPrefixMatch != nil {
                        shouldAddSpaceAfterNationalPrefix = true
                    }
                }
                return tempTemplate
            }
        }
        catch { }
        return nil
    }
    
    func getFormattingTemplate(numberPattern: String, numberFormat: String, rawNumber: String) -> String? {
        do {
            let matches =  try regex.matchedStringByRegex(numberPattern, string: longPhoneNumber)
            if let match = matches.first {
                if match.characters.count < rawNumber.characters.count {
                    return nil
                }
                var template = regex.replaceStringByRegex(numberPattern, string: match, template: numberFormat)
                template = regex.replaceStringByRegex("9", string: template, template: digitPlaceholder)
                return template
            }
        }
        catch {
        
        }
        return nil
    }
    
    func applyFormattingTemplate(template: String, rawNumber: String) -> String {
        var rebuiltString = String()
        var rebuiltIndex = 0
        for character in template.characters {
            if character == digitPlaceholder.characters.first {
                if rebuiltIndex < rawNumber.characters.count {
                    let nationalCharacterIndex = rawNumber.startIndex.advancedBy(rebuiltIndex)
                    rebuiltString.append(rawNumber[nationalCharacterIndex])
                    rebuiltIndex++
                }
            }
            else {
                rebuiltString.append(character)
            }
        }
        if rebuiltIndex < rawNumber.characters.count {
            let nationalCharacterIndex = rawNumber.startIndex.advancedBy(rebuiltIndex)
            let remainingNationalNumber: String = rawNumber.substringFromIndex(nationalCharacterIndex)
            rebuiltString.appendContentsOf(remainingNationalNumber)
        }
        rebuiltString = rebuiltString.stringByTrimmingCharactersInSet(NSCharacterSet.alphanumericCharacterSet().invertedSet)
        return rebuiltString
    }
    
}