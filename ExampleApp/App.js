/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 * @flow
 */

import {
  NativeModules,
  Platform,
  NativeEventEmitter,
  DeviceEventEmitter,
  Text,
  View,
  Button,
  Alert,
  PermissionsAndroid,
} from 'react-native';

import React, { Component } from 'react';

import {
  AppState
} from 'react-native'

const { GoogleSpeechApi } = NativeModules;

const EventEmitter = Platform.select({
  android: DeviceEventEmitter,
  ios: new NativeEventEmitter(GoogleSpeechApi),
});

export default class App extends Component {

  constructor(props) {
    super(props);
    this.state = {
      currentText: "",
      previousTexts: "",
      button: "Start listening"
    };
  }

  componentDidMount(){
    AppState.addEventListener('change', this.onAppStateChange)
    GoogleSpeechApi.setApiKey("Your google access token")
    if (Platform.OS === 'ios') {
      GoogleSpeechApi.setSpeechContextPhrases(["weather"])
    }
    EventEmitter.addListener('onSpeechRecognized', (event) => {
      var previousTexts = this.state.previousTexts;
      var currentText = event['text']
      var button = "I'm listening"
      if (event['isFinal']){
        currentText = ""
        previousTexts = event['text'] + "\n" + previousTexts;
        button = "Start listening"
      }
      this.setState({
        currentText: currentText,
        previousTexts: previousTexts,
        button: button
      });
    });

    EventEmitter.addListener('onStartError', (error) => {
      var previousTexts = this.state.previousTexts;
      this.setState({
        currentText: "",
        button: "Start listening"
      });
      Alert.alert(
        "Error occured",
        error['message']
      );
    });

    EventEmitter.addListener('onStopError', (error) => {
      var previousTexts = this.state.previousTexts;
      this.setState({
        currentText: "",
        button: "Start listening"
      });
      Alert.alert(
        "Error occured",
        error['message']
      );
    });

    EventEmitter.addListener('onSpeechRecognizedError', (error) => {
        this.setState({
          button: "Start listening"
        })
        Alert.alert(
          "Error occured",
          error['message']
        );
    });
  }

  onAppStateChange = state => {
    if (state.match(/inactive|background/)) {
      GoogleSpeechApi.stop()
    }
  }

  startListening = () => {
    this.setState({
      button: "I'm listening"
    })
    GoogleSpeechApi.start()
  }

  requestAudioPermission = async () => {
    try {
      const granted = await PermissionsAndroid.request(
        PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
        {
          title: 'Record Audio Permission',
          message:
            'App needs access to your microphone ' +
            'so you can convert speech to text.',
          buttonNeutral: 'Ask Me Later',
          buttonNegative: 'Cancel',
          buttonPositive: 'OK',
        },
      );
      if (granted === PermissionsAndroid.RESULTS.GRANTED) {
        console.log('permission granted');
        this.startListening();
      } else {
        console.log('permission denied');
      }
    } catch (err) {
      console.warn(err);
    }
  }

  render() {
    return (
      <View style={{ margin: 30 }}>
        <Text>{this.state.currentText}</Text>
        <Text>{this.state.previousTexts}</Text>
        <Button
          title={this.state.button}
          onPress={Platform.OS === 'ios' ? this.startListening : this.requestAudioPermission}/>
      </View>
    );
  }
}
